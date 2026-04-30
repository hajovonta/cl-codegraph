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

;;; Advanced queries

(defun fan-out (graph uri)
  "Number of functions URI calls."
  (length (ariadne:get-triples graph :subject uri :predicate +calls+)))

(defun fan-in (graph uri)
  "Number of functions that call URI."
  (length (ariadne:get-triples graph :subject uri :predicate +called-by+)))

(defun impact-of (graph uri)
  "Return all symbols that transitively depend on URI (callers, callers of callers, etc.)."
  (let ((visited (make-hash-table :test 'equal))
        (result '())
        (queue '()))
    (setf (gethash uri visited) t)
    ;; Seed with direct callers
    (dolist (tr (ariadne:get-triples graph :subject uri :predicate +called-by+))
      (let ((caller (ariadne:triple-object tr)))
        (unless (gethash caller visited)
          (setf (gethash caller visited) t)
          (push caller queue)
          (push caller result))))
    ;; BFS through callers
    (loop while queue do
      (let ((current (pop queue)))
        (dolist (tr (ariadne:get-triples graph :subject current :predicate +called-by+))
          (let ((caller (ariadne:triple-object tr)))
            (unless (gethash caller visited)
              (setf (gethash caller visited) t)
              (push caller queue)
              (push caller result))))))
    result))

(defun find-cycles (graph)
  "Find all cycles in the call graph. Returns a list of cycles,
each cycle being a list of URIs forming the loop."
  (let ((nodes '())
        (visited (make-hash-table :test 'equal))
        (on-stack (make-hash-table :test 'equal))
        (cycles '()))
    ;; Collect all callable nodes
    (dolist (tr (ariadne:get-triples graph :predicate +calls+))
      (pushnew (ariadne:triple-subject tr) nodes :test #'string=)
      (pushnew (ariadne:triple-object tr) nodes :test #'string=))
    ;; DFS for back edges
    (labels ((dfs (node path)
               (setf (gethash node visited) t)
               (setf (gethash node on-stack) t)
               (dolist (tr (ariadne:get-triples graph :subject node :predicate +calls+))
                 (let ((next (ariadne:triple-object tr)))
                   (cond
                     ((gethash next on-stack)
                      ;; Found a cycle — extract it
                      (let ((cycle-start (position next path :test #'string=)))
                        (when cycle-start
                          (push (append (subseq path cycle-start) (list next)) cycles))))
                     ((not (gethash next visited))
                      (dfs next (append path (list next)))))))
               (setf (gethash node on-stack) nil)))
      (dolist (node nodes)
        (unless (gethash node visited)
          (dfs node (list node)))))
    cycles))

;;; Incremental rebuild

(defun refresh-graph (graph package-designator &key include-internal include-external-calls)
  "Rebuild GRAPH from PACKAGE-DESIGNATOR and return a diff-summary plist
showing what changed (:added N :removed M)."
  (let* ((old-triples (make-hash-table :test 'equal))
         (added 0)
         (removed 0))
    ;; Snapshot old state
    (dolist (tr (ariadne:get-triples graph))
      (setf (gethash (triple-key tr) old-triples) t))
    ;; Rebuild
    (let ((pkg (find-package package-designator)))
      (when (null pkg)
        (error "Package ~A not found" package-designator))
      (ariadne:clear-graph graph)
      (index-package graph pkg include-external-calls include-internal))
    ;; Diff
    (let ((new-triples (make-hash-table :test 'equal)))
      (dolist (tr (ariadne:get-triples graph))
        (let ((key (triple-key tr)))
          (setf (gethash key new-triples) t)
          (unless (gethash key old-triples)
            (incf added))))
      (maphash (lambda (key _)
                 (declare (ignore _))
                 (unless (gethash key new-triples)
                   (incf removed)))
               old-triples))
    (list :added added :removed removed)))

;;; REPL integration

(defun describe-symbol (graph uri)
  "Return a formatted string describing a symbol in the graph."
  (with-output-to-string (s)
    (let ((type-triples (ariadne:get-triples graph :subject uri :predicate +type+))
          (calls (what-calls graph uri))
          (callers (who-calls-p graph uri))
          (ll (ariadne:get-triples graph :subject uri :predicate +lambda-list+))
          (doc (ariadne:get-triples graph :subject uri :predicate +docstring+)))
      (format s "~A~%" uri)
      (when type-triples
        (format s "  type: ~A~%" (ariadne:triple-object (first type-triples))))
      (when ll
        (format s "  args: ~A~%" (ariadne:triple-object (first ll))))
      (when doc
        (format s "  doc:  ~A~%" (ariadne:triple-object (first doc))))
      (when calls
        (format s "  calls: ~{~A~^, ~}~%" calls))
      (when callers
        (format s "  called-by: ~{~A~^, ~}~%" callers)))))

(defun summary (graph)
  "Return a formatted overview of the graph."
  (with-output-to-string (s)
    (let ((types (make-hash-table :test 'equal))
          (call-count (length (ariadne:get-triples graph :predicate +calls+))))
      (dolist (tr (ariadne:get-triples graph :predicate +type+))
        (incf (gethash (ariadne:triple-object tr) types 0)))
      (format s "Graph: ~A triples~%~%" (ariadne:triple-count graph))
      (format s "Symbols:~%")
      (maphash (lambda (type count)
                 (format s "  ~A: ~A~%" type count))
               types)
      (format s "~%call edges: ~A~%" call-count))))

;;; Package hygiene

(defun unused-packages (graph package-designator)
  "Return names of packages in PACKAGE-DESIGNATOR's use-list that have no
calls from the graphed symbols. Requires :include-external-calls graph."
  (let* ((pkg (find-package package-designator))
         (used-pkgs (remove (find-package :cl) (package-use-list pkg)))
         (called-pkgs (make-hash-table :test 'equal)))
    ;; Find all external packages that have cg:calls edges pointing to them
    (dolist (tr (ariadne:get-triples graph :predicate +calls+))
      (let ((callee (ariadne:triple-object tr)))
        ;; Extract package from URI (format: "pkg:sym" or "pkg::sym")
        (let ((colon (position #\: callee)))
          (when colon
            (setf (gethash (subseq callee 0 colon) called-pkgs) t)))))
    ;; Check which used packages have no calls
    (loop for p in used-pkgs
          for name = (string-downcase (package-name p))
          unless (gethash name called-pkgs)
          collect name)))
