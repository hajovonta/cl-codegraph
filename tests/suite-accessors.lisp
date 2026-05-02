;;;; tests/suite-accessors.lisp — Inlined accessor call detection and slot-of-class info

(in-package #:cl-codegraph-tests)

(defpackage #:cg-accessor-pkg
  (:use #:cl)
  (:export #:my-thing #:my-thing-name #:my-thing-value #:use-thing))

(in-package #:cg-accessor-pkg)

(defstruct my-thing
  name
  value)

(defun use-thing (x)
  (list (my-thing-name x) (my-thing-value x)))

(in-package #:cl-codegraph-tests)

(def-suite :accessors :in :cl-codegraph
  :description "Inlined accessor detection and slot-of-class")

(in-suite :accessors)

(test accessor-callers-detected
  "Functions calling struct accessors show up via who-calls"
  (let ((g (cl-codegraph:build-graph :cg-accessor-pkg)))
    (is (ariadne:has-triple-p g "cg-accessor-pkg:use-thing" "cg:calls" "cg-accessor-pkg:my-thing-name"))
    (is (ariadne:has-triple-p g "cg-accessor-pkg:use-thing" "cg:calls" "cg-accessor-pkg:my-thing-value"))))

(test accessor-shows-slot-of
  "Struct accessors show which struct they belong to"
  (let ((g (cl-codegraph:build-graph :cg-accessor-pkg)))
    (is (ariadne:has-triple-p g "cg-accessor-pkg:my-thing-name" "cg:slotOf" "cg-accessor-pkg:my-thing"))))
