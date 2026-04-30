;;;; tests/suite-var-value.lisp — Show variable/constant values and references

(in-package #:cl-codegraph-tests)

(defpackage #:cg-val-pkg
  (:use #:cl)
  (:export #:+my-const+ #:*my-var* #:uses-const))

(in-package #:cg-val-pkg)
(defconstant +my-const+ 42)
(defvar *my-var* "hello")
(defun uses-const () +my-const+)

(in-package #:cl-codegraph-tests)

(def-suite :var-value :in :cl-codegraph
  :description "Variable/constant values and references in graph")

(in-suite :var-value)

(test constant-has-value-triple
  "Constants get a cg:value triple"
  (let ((g (cl-codegraph:build-graph :cg-val-pkg)))
    (is (has-triple-p g "cg-val-pkg:+my-const+" "cg:value" "42"))))

(test variable-has-value-triple
  "Special variables get a cg:value triple"
  (let ((g (cl-codegraph:build-graph :cg-val-pkg)))
    (is (has-triple-p g "cg-val-pkg:*my-var*" "cg:value" "\"hello\""))))

(test constant-has-referenced-by
  "Constants track who references them"
  (let ((g (cl-codegraph:build-graph :cg-val-pkg)))
    (is (has-triple-p g "cg-val-pkg:uses-const" "cg:readsVar" "cg-val-pkg:+my-const+"))))
