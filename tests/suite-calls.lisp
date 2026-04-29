;;;; tests/suite-calls.lisp — Call graph relationship tests

(in-package #:cl-codegraph-tests)

;;; A test package with known call relationships

(defpackage #:cg-call-pkg
  (:use #:cl)
  (:export #:caller-fn
           #:callee-fn
           #:intermediate-fn
           #:isolated-fn))

(in-package #:cg-call-pkg)

(defun callee-fn (x) (1+ x))
(defun intermediate-fn (x) (callee-fn x))
(defun caller-fn (x) (intermediate-fn x))
(defun isolated-fn () :alone)

(in-package #:cl-codegraph-tests)

(def-suite :call-graph :in :cl-codegraph
  :description "Call relationship triples via sb-introspect")

(in-suite :call-graph)

(test caller-calls-callee
  "Direct call relationships are recorded"
  (let ((g (cl-codegraph:build-graph :cg-call-pkg)))
    (is (has-triple-p g "cg-call-pkg:caller-fn" "cg:calls" "cg-call-pkg:intermediate-fn"))))

(test intermediate-calls-callee
  "Transitive calls are recorded as direct edges"
  (let ((g (cl-codegraph:build-graph :cg-call-pkg)))
    (is (has-triple-p g "cg-call-pkg:intermediate-fn" "cg:calls" "cg-call-pkg:callee-fn"))))

(test called-by-is-inverse
  "calledBy is the inverse of calls"
  (let ((g (cl-codegraph:build-graph :cg-call-pkg)))
    (is (has-triple-p g "cg-call-pkg:intermediate-fn" "cg:calledBy" "cg-call-pkg:caller-fn"))))

(test no-transitive-closure
  "Only direct calls are recorded, not transitive"
  (let ((g (cl-codegraph:build-graph :cg-call-pkg)))
    (is (not (has-triple-p g "cg-call-pkg:caller-fn" "cg:calls" "cg-call-pkg:callee-fn")))))

(test isolated-function-has-no-calls
  "A function that calls nothing has no cg:calls triples"
  (let ((g (cl-codegraph:build-graph :cg-call-pkg)))
    (is (= 0 (length (triples-with g :subject "cg-call-pkg:isolated-fn"
                                      :predicate "cg:calls"))))))

(test isolated-function-not-called
  "A function nobody calls has no cg:calledBy triples"
  (let ((g (cl-codegraph:build-graph :cg-call-pkg)))
    (is (= 0 (length (triples-with g :subject "cg-call-pkg:isolated-fn"
                                      :predicate "cg:calledBy"))))))
