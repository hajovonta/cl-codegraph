;;;; tests/suite-monitor-vars.lisp — Monitor picks up defvar/defparameter/defclass

(in-package #:cl-codegraph-tests)

(defpackage #:cg-monvar-pkg
  (:use #:cl)
  (:export #:*config* #:monvar-class #:monvar-fn))

(in-package #:cg-monvar-pkg)
(defvar *config* :initial)
(defclass monvar-class () ((slot-x :initarg :x)))
(defun monvar-fn () *config*)

(in-package #:cl-codegraph-tests)

(def-suite :monitor-vars :in :cl-codegraph
  :description "Monitor detects defvar/defparameter/defclass changes")

(in-suite :monitor-vars)

(test monitor-detects-defvar-change
  "Redefining a special variable marks it dirty and updates the graph"
  (cl-codegraph:monitor :cg-monvar-pkg)
  (unwind-protect
       (progn
         (eval '(defparameter cg-monvar-pkg:*config* :changed))
         (let ((g (cl-codegraph:graph :cg-monvar-pkg)))
           ;; Variable should still be in the graph
           (is (ariadne:has-triple-p g "cg-monvar-pkg:*config*" "rdf:type" "special-variable"))))
    (eval '(defvar cg-monvar-pkg:*config* :initial))
    (cl-codegraph:unmonitor :cg-monvar-pkg)))

(test monitor-detects-defclass-change
  "Redefining a class marks it dirty and updates the graph"
  (cl-codegraph:monitor :cg-monvar-pkg)
  (unwind-protect
       (progn
         ;; Add a new slot
         (eval '(defclass cg-monvar-pkg:monvar-class ()
                  ((cg-monvar-pkg::slot-x :initarg :x)
                   (cg-monvar-pkg::slot-y :initarg :y))))
         (let ((g (cl-codegraph:graph :cg-monvar-pkg)))
           ;; New slot should appear
           (is (ariadne:has-triple-p g "cg-monvar-pkg:monvar-class" "cg:hasSlot"
                                     "cg-monvar-pkg:monvar-class.slot-y"))))
    ;; Restore
    (eval '(defclass cg-monvar-pkg:monvar-class ()
              ((cg-monvar-pkg::slot-x :initarg :x))))
    (cl-codegraph:unmonitor :cg-monvar-pkg)))
