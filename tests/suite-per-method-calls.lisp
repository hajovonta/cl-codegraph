;;;; tests/suite-per-method-calls.lisp — Per-method call edges for GFs

(in-package #:cl-codegraph-tests)

(defpackage #:cg-method-pkg
  (:use #:cl)
  (:export #:process-item #:handle-string #:handle-number #:my-gf))

(in-package #:cg-method-pkg)

(defun handle-string (s) (string-upcase s))
(defun handle-number (n) (1+ n))

(defgeneric my-gf (x))
(defmethod my-gf ((x string)) (handle-string x))
(defmethod my-gf ((x number)) (handle-number x))

(in-package #:cl-codegraph-tests)

(def-suite :per-method-calls :in :cl-codegraph
  :description "Per-method call edges for generic functions")

(in-suite :per-method-calls)

(test method-nodes-have-calls
  "Individual method nodes have their own cg:calls edges"
  (let ((g (cl-codegraph:build-graph :cg-method-pkg)))
    ;; The string method calls handle-string
    (let ((string-method-calls
            (ariadne:get-triples g :subject "cg-method-pkg:my-gf/method/string"
                                   :predicate "cg:calls")))
      (is (some (lambda (tr)
                  (string= (ariadne:triple-object tr) "cg-method-pkg:handle-string"))
                string-method-calls)))
    ;; The number method calls handle-number
    (let ((number-method-calls
            (ariadne:get-triples g :subject "cg-method-pkg:my-gf/method/number"
                                   :predicate "cg:calls")))
      (is (some (lambda (tr)
                  (string= (ariadne:triple-object tr) "cg-method-pkg:handle-number"))
                number-method-calls)))))

(test method-calls-dont-bleed
  "String method doesn't show handle-number as callee"
  (let ((g (cl-codegraph:build-graph :cg-method-pkg)))
    (is (not (ariadne:has-triple-p g "cg-method-pkg:my-gf/method/string"
                                   "cg:calls" "cg-method-pkg:handle-number")))))

(test gf-still-has-aggregate-calls
  "The GF node still has the flattened calls (union of all methods)"
  (let ((g (cl-codegraph:build-graph :cg-method-pkg)))
    (is (ariadne:has-triple-p g "cg-method-pkg:my-gf" "cg:calls" "cg-method-pkg:handle-string"))
    (is (ariadne:has-triple-p g "cg-method-pkg:my-gf" "cg:calls" "cg-method-pkg:handle-number"))))
