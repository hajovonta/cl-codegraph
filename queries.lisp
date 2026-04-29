;;;; queries.lisp — Convenience query functions over a codegraph

(in-package #:cl-codegraph)

(defun what-calls (graph symbol-uri)
  "Return list of URIs that SYMBOL-URI calls."
  (mapcar #'ariadne:triple-object
          (ariadne:get-triples graph :subject symbol-uri :predicate +calls+)))

(defun who-calls-p (graph symbol-uri)
  "Return list of URIs that call SYMBOL-URI."
  (mapcar #'ariadne:triple-object
          (ariadne:get-triples graph :subject symbol-uri :predicate +called-by+)))

(defun dead-exports (graph)
  "Return list of exported function/generic URIs that are never called within the package."
  (let ((all-callees (make-hash-table :test 'equal)))
    ;; Collect everything that appears as a callee
    (dolist (tr (ariadne:get-triples graph :predicate +calls+))
      (setf (gethash (ariadne:triple-object tr) all-callees) t))
    ;; Find exported callables not in the callee set
    (let ((dead '()))
      (dolist (tr (ariadne:get-triples graph :predicate +type+))
        (when (member (ariadne:triple-object tr) '("function" "generic-function") :test #'string=)
          (unless (gethash (ariadne:triple-subject tr) all-callees)
            (push (ariadne:triple-subject tr) dead))))
      dead)))

(defun undocumented-exports (graph)
  "Return list of exported symbol URIs that have no docstring."
  (let ((documented (make-hash-table :test 'equal)))
    (dolist (tr (ariadne:get-triples graph :predicate +docstring+))
      (setf (gethash (ariadne:triple-subject tr) documented) t))
    (let ((undoc '()))
      (dolist (tr (ariadne:get-triples graph :predicate +type+))
        (unless (gethash (ariadne:triple-subject tr) documented)
          (push (ariadne:triple-subject tr) undoc)))
      undoc)))

(defun call-chain (graph from-uri to-uri)
  "Find a call path from FROM-URI to TO-URI. Returns list of URIs or nil."
  (let ((visited (make-hash-table :test 'equal))
        (queue (list (list from-uri))))
    (setf (gethash from-uri visited) t)
    (loop
      (when (null queue) (return nil))
      (let* ((path (pop queue))
             (current (car (last path))))
        (when (string= current to-uri)
          (return path))
        (dolist (tr (ariadne:get-triples graph :subject current :predicate +calls+))
          (let ((next (ariadne:triple-object tr)))
            (unless (gethash next visited)
              (setf (gethash next visited) t)
              (push (append path (list next)) queue))))))))

;;; Visualization

(defun export-dot (graph &key predicates)
  "Export GRAPH as a Graphviz DOT string. If PREDICATES is given, only include
edges with those predicates."
  (with-output-to-string (s)
    (format s "digraph codegraph {~%")
    (format s "  rankdir=LR;~%")
    (format s "  node [shape=box, fontsize=10];~%")
    (let ((triples (if predicates
                       (loop for p in predicates
                             nconc (ariadne:get-triples graph :predicate p))
                       (ariadne:get-triples graph))))
      (dolist (tr triples)
        (let ((subj (ariadne:triple-subject tr))
              (pred (ariadne:triple-predicate tr))
              (obj (ariadne:triple-object tr)))
          (format s "  ~S -> ~S [label=~S];~%" subj obj pred))))
    (format s "}~%")))

(defun neighborhood (graph uri &key (depth 1))
  "Extract a subgraph containing all triples within DEPTH hops of URI."
  (let ((sub (ariadne:make-graph :name (format nil "neighborhood/~A" uri)))
        (visited (make-hash-table :test 'equal))
        (frontier (list uri)))
    (setf (gethash uri visited) t)
    (dotimes (i (1+ depth))
      (let ((next-frontier '()))
        (dolist (node frontier)
          ;; Triples where node is subject
          (dolist (tr (ariadne:get-triples graph :subject node))
            (ariadne:add-triple sub (ariadne:triple-subject tr)
                                (ariadne:triple-predicate tr)
                                (ariadne:triple-object tr))
            (when (and (< i depth)
                       (not (gethash (ariadne:triple-object tr) visited)))
              (setf (gethash (ariadne:triple-object tr) visited) t)
              (push (ariadne:triple-object tr) next-frontier)))
          ;; Triples where node is object
          (dolist (tr (ariadne:get-triples graph :object node))
            (ariadne:add-triple sub (ariadne:triple-subject tr)
                                (ariadne:triple-predicate tr)
                                (ariadne:triple-object tr))
            (when (and (< i depth)
                       (not (gethash (ariadne:triple-subject tr) visited)))
              (setf (gethash (ariadne:triple-subject tr) visited) t)
              (push (ariadne:triple-subject tr) next-frontier))))
        (setf frontier next-frontier)))
    sub))

;;; Diff

(defun triple-key (tr)
  (list (ariadne:triple-subject tr) (ariadne:triple-predicate tr) (ariadne:triple-object tr)))

(defun diff-graphs (old new)
  "Compare OLD and NEW graphs. Returns plist with :added and :removed triple lists."
  (let ((old-set (make-hash-table :test 'equal))
        (new-set (make-hash-table :test 'equal))
        (added '())
        (removed '()))
    (dolist (tr (ariadne:get-triples old))
      (setf (gethash (triple-key tr) old-set) t))
    (dolist (tr (ariadne:get-triples new))
      (setf (gethash (triple-key tr) new-set) t)
      (unless (gethash (triple-key tr) old-set)
        (push tr added)))
    (dolist (tr (ariadne:get-triples old))
      (unless (gethash (triple-key tr) new-set)
        (push tr removed)))
    (list :added added :removed removed)))

(defun diff-summary (old new)
  "Return a plist with counts: :added N :removed M."
  (let ((diff (diff-graphs old new)))
    (list :added (length (getf diff :added))
          :removed (length (getf diff :removed)))))
