;;;; tests/suite-metadata.lisp — Source location, lambda-list, docstring metadata

(in-package #:cl-codegraph-tests)

(defpackage #:cg-meta-pkg
  (:use #:cl)
  (:export #:documented-fn
           #:multi-arg-fn
           #:meta-class))

(in-package #:cg-meta-pkg)

(defun documented-fn (x)
  "A function with a docstring."
  (1+ x))

(defun multi-arg-fn (a b &key (verbose nil))
  "Multiple arguments."
  (declare (ignore verbose))
  (+ a b))

(defclass meta-class ()
  ((slot-a :initarg :a :documentation "Slot A doc"))
  (:documentation "A documented class."))

(in-package #:cl-codegraph-tests)

(def-suite :metadata :in :cl-codegraph
  :description "Source location, lambda-list, and docstring metadata")

(in-suite :metadata)

(test function-has-lambda-list
  "Functions get a cg:lambdaList triple"
  (let ((g (cl-codegraph:build-graph :cg-meta-pkg)))
    (let ((triples (triples-with g :subject "cg-meta-pkg:documented-fn"
                                   :predicate "cg:lambdaList")))
      (is (= 1 (length triples)))
      (is (string= "(X)" (cl-codegraph::literal-value (ariadne:triple-object (first triples))))))))

(test multi-arg-lambda-list
  "Complex lambda lists are captured"
  (let ((g (cl-codegraph:build-graph :cg-meta-pkg)))
    (let ((triples (triples-with g :subject "cg-meta-pkg:multi-arg-fn"
                                   :predicate "cg:lambdaList")))
      (is (= 1 (length triples)))
      (is (search "&KEY" (cl-codegraph::literal-value (ariadne:triple-object (first triples))))))))

(test function-has-docstring
  "Functions with docstrings get a cg:docstring triple"
  (let ((g (cl-codegraph:build-graph :cg-meta-pkg)))
    (let ((triples (triples-with g :subject "cg-meta-pkg:documented-fn"
                                   :predicate "cg:docstring")))
      (is (= 1 (length triples)))
      (is (string= "A function with a docstring."
                    (cl-codegraph::literal-value (ariadne:triple-object (first triples))))))))

(test class-has-docstring
  "Classes with docstrings get a cg:docstring triple"
  (let ((g (cl-codegraph:build-graph :cg-meta-pkg)))
    (let ((triples (triples-with g :subject "cg-meta-pkg:meta-class"
                                   :predicate "cg:docstring")))
      (is (= 1 (length triples)))
      (is (string= "A documented class."
                    (cl-codegraph::literal-value (ariadne:triple-object (first triples))))))))

(test function-has-source-location
  "Functions get a cg:sourceFile triple when source is known"
  (let ((g (cl-codegraph:build-graph :cg-meta-pkg)))
    (let ((triples (triples-with g :subject "cg-meta-pkg:documented-fn"
                                   :predicate "cg:sourceFile")))
      (is (or (= 0 (length triples))
              (ariadne:rdf-literal-p (ariadne:triple-object (first triples))))))))
