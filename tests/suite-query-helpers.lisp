;;;; tests/suite-query-helpers.lisp — Convenience query functions

(in-package #:cl-codegraph-tests)

(defpackage #:cg-query-pkg
  (:use #:cl)
  (:export #:entry-point
           #:helper-a
           #:helper-b
           #:dead-fn
           #:undoc-fn
           #:documented-fn
           #:*my-var*))

(in-package #:cg-query-pkg)

(defvar *my-var* nil)

(defun helper-b (x) (1+ x))
(defun helper-a (x) (helper-b x))
(defun entry-point (x) (helper-a x))
(defun dead-fn () :never-called)

(defun undoc-fn () :no-docs)

(defun documented-fn ()
  "I have docs."
  :ok)

(in-package #:cl-codegraph-tests)

(def-suite :query-helpers :in :cl-codegraph
  :description "Convenience query functions")

(in-suite :query-helpers)

(defvar *qg* nil)

(defmacro with-query-graph (&body body)
  `(let ((*qg* (cl-codegraph:build-graph :cg-query-pkg)))
     ,@body))

;;; what-calls / called-by

(test what-calls-returns-callees
  "what-calls returns the list of symbols that a function calls"
  (with-query-graph
    (let ((result (cl-codegraph:what-calls *qg* "cg-query-pkg:entry-point")))
      (is (member "cg-query-pkg:helper-a" result :test #'string=)))))

(test who-calls-returns-callers
  "who-calls-p returns the list of symbols that call a function"
  (with-query-graph
    (let ((result (cl-codegraph:who-calls-p *qg* "cg-query-pkg:helper-a")))
      (is (member "cg-query-pkg:entry-point" result :test #'string=)))))

;;; dead exports

(test dead-exports-finds-uncalled
  "dead-exports returns exported functions that nothing in the package calls"
  (with-query-graph
    (let ((dead (cl-codegraph:dead-exports *qg*)))
      (is (member "cg-query-pkg:dead-fn" dead :test #'string=))
      ;; entry-point is also dead (nobody calls it), but helper-a is not
      (is (not (member "cg-query-pkg:helper-a" dead :test #'string=)))
      (is (not (member "cg-query-pkg:helper-b" dead :test #'string=))))))

;;; undocumented exports

(test undocumented-finds-missing-docs
  "undocumented-exports returns symbols without docstrings"
  (with-query-graph
    (let ((undoc (cl-codegraph:undocumented-exports *qg*)))
      (is (member "cg-query-pkg:undoc-fn" undoc :test #'string=))
      (is (not (member "cg-query-pkg:documented-fn" undoc :test #'string=))))))

;;; call-chain

(test call-chain-finds-path
  "call-chain returns a path from caller to callee"
  (with-query-graph
    (let ((chain (cl-codegraph:call-chain *qg* "cg-query-pkg:entry-point"
                                               "cg-query-pkg:helper-b")))
      (is (not (null chain)))
      (is (string= (first chain) "cg-query-pkg:entry-point"))
      (is (string= (car (last chain)) "cg-query-pkg:helper-b"))
      (is (= 3 (length chain))))))

(test call-chain-returns-nil-when-no-path
  "call-chain returns nil when no path exists"
  (with-query-graph
    (let ((chain (cl-codegraph:call-chain *qg* "cg-query-pkg:dead-fn"
                                               "cg-query-pkg:helper-b")))
      (is (null chain)))))
