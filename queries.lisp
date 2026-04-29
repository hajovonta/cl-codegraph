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
