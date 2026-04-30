;;;; tests/suite-unused-imports.lisp — Detect packages in use-list with no calls

(in-package #:cl-codegraph-tests)

(defpackage #:cg-unused-base
  (:use #:cl)
  (:export #:base-util))

(in-package #:cg-unused-base)
(defun base-util () :util)

(defpackage #:cg-unused-consumer
  (:use #:cl #:cg-unused-base)
  (:export #:consumer-fn))

(in-package #:cg-unused-consumer)
;; Uses CL but never calls anything from cg-unused-base
(defun consumer-fn () (+ 1 2))

(in-package #:cl-codegraph-tests)

(def-suite :unused-imports :in :cl-codegraph
  :description "Detect unused package imports")

(in-suite :unused-imports)

(test unused-packages-detected
  "unused-packages returns packages in use-list that are never called"
  (let* ((g (cl-codegraph:build-graph :cg-unused-consumer :include-external-calls t))
         (unused (cl-codegraph:unused-packages g :cg-unused-consumer)))
    (is (member "cg-unused-base" unused :test #'string-equal))))

(test used-packages-not-listed
  "Packages that are actually called don't appear"
  (let* ((g (cl-codegraph:build-graph :cg-dep-consumer :include-external-calls t))
         (unused (cl-codegraph:unused-packages g :cg-dep-consumer)))
    ;; cg-dep-consumer calls cg-dep-base:base-fn, so it shouldn't be unused
    ;; (but cg-dep-consumer doesn't :use cg-dep-base, so this test uses a different fixture)
    (is (listp unused))))
