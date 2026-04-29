;;;; tests/suite-advanced-queries.lisp — Circular calls, impact analysis, metrics

(in-package #:cl-codegraph-tests)

(defpackage #:cg-cycle-pkg
  (:use #:cl)
  (:export #:cycle-a #:cycle-b #:no-cycle-fn))

(in-package #:cg-cycle-pkg)
(defun no-cycle-fn () :leaf)
(defun cycle-b (x) (when (> x 0) (cycle-a (1- x))))
(defun cycle-a (x) (cycle-b x))

(in-package #:cl-codegraph-tests)

(def-suite :advanced-queries :in :cl-codegraph
  :description "Circular calls, impact analysis, metrics")

(in-suite :advanced-queries)

;;; Circular call detection

(test find-cycles-detects-mutual-recursion
  "find-cycles returns cycles in the call graph"
  (let* ((g (cl-codegraph:build-graph :cg-cycle-pkg))
         (cycles (cl-codegraph:find-cycles g)))
    (is (not (null cycles)))
    ;; Should find the cycle-a <-> cycle-b cycle
    (is (some (lambda (cycle)
                (and (member "cg-cycle-pkg:cycle-a" cycle :test #'string=)
                     (member "cg-cycle-pkg:cycle-b" cycle :test #'string=)))
              cycles))))

(test find-cycles-ignores-acyclic
  "Acyclic functions don't appear in cycles"
  (let* ((g (cl-codegraph:build-graph :cg-cycle-pkg))
         (cycles (cl-codegraph:find-cycles g)))
    (is (not (some (lambda (cycle)
                     (member "cg-cycle-pkg:no-cycle-fn" cycle :test #'string=))
                   cycles)))))

;;; Impact analysis

(test impact-of-returns-dependents
  "impact-of returns all symbols that transitively depend on a given symbol"
  (let* ((g (cl-codegraph:build-graph :cg-call-pkg))
         (impact (cl-codegraph:impact-of g "cg-call-pkg:callee-fn")))
    ;; intermediate-fn calls callee-fn, caller-fn calls intermediate-fn
    (is (member "cg-call-pkg:intermediate-fn" impact :test #'string=))
    (is (member "cg-call-pkg:caller-fn" impact :test #'string=))))

(test impact-of-leaf-is-empty
  "A function nothing calls has no impact"
  (let* ((g (cl-codegraph:build-graph :cg-call-pkg))
         (impact (cl-codegraph:impact-of g "cg-call-pkg:caller-fn")))
    (is (null impact))))

;;; Fan-in / fan-out

(test fan-out-counts-callees
  "fan-out returns the number of functions a symbol calls"
  (let ((g (cl-codegraph:build-graph :cg-call-pkg)))
    (is (= 1 (cl-codegraph:fan-out g "cg-call-pkg:caller-fn")))
    (is (= 0 (cl-codegraph:fan-out g "cg-call-pkg:callee-fn")))))

(test fan-in-counts-callers
  "fan-in returns the number of functions that call a symbol"
  (let ((g (cl-codegraph:build-graph :cg-call-pkg)))
    (is (= 0 (cl-codegraph:fan-in g "cg-call-pkg:caller-fn")))
    (is (= 1 (cl-codegraph:fan-in g "cg-call-pkg:callee-fn")))))
