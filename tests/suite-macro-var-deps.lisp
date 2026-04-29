;;;; tests/suite-macro-var-deps.lisp — Macro expansion and variable dependency tracking

(in-package #:cl-codegraph-tests)

(defpackage #:cg-macro-pkg
  (:use #:cl)
  (:export #:my-macro
           #:uses-macro-fn
           #:*my-special*
           #:reads-special
           #:writes-special))

(in-package #:cg-macro-pkg)

(defvar *my-special* 0)

(defmacro my-macro (form)
  `(progn ,form))

(defun uses-macro-fn ()
  (my-macro (+ 1 2)))

(defun reads-special ()
  *my-special*)

(defun writes-special (val)
  (setf *my-special* val))

(in-package #:cl-codegraph-tests)

(def-suite :macro-var-deps :in :cl-codegraph
  :description "Macro usage and special variable dependency tracking")

(in-suite :macro-var-deps)

(test macro-expansion-tracked
  "Functions that expand a macro get a cg:expandsMacro triple"
  (let ((g (cl-codegraph:build-graph :cg-macro-pkg)))
    (is (has-triple-p g "cg-macro-pkg:uses-macro-fn" "cg:expandsMacro"
                      "cg-macro-pkg:my-macro"))))

(test variable-read-tracked
  "Functions that read a special variable get a cg:readsVar triple"
  (let ((g (cl-codegraph:build-graph :cg-macro-pkg)))
    (is (has-triple-p g "cg-macro-pkg:reads-special" "cg:readsVar"
                      "cg-macro-pkg:*my-special*"))))

(test variable-write-tracked
  "Functions that write a special variable get a cg:writesVar triple"
  (let ((g (cl-codegraph:build-graph :cg-macro-pkg)))
    (is (has-triple-p g "cg-macro-pkg:writes-special" "cg:writesVar"
                      "cg-macro-pkg:*my-special*"))))
