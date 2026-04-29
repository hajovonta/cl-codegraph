;;;; tests/suite-incremental.lisp — Selective rebuild and change tracking

(in-package #:cl-codegraph-tests)

(defpackage #:cg-incr-pkg
  (:use #:cl)
  (:export #:incr-fn-a #:incr-fn-b))

(in-package #:cg-incr-pkg)
(defun incr-fn-b () :original)
(defun incr-fn-a () (incr-fn-b))

(in-package #:cl-codegraph-tests)

(def-suite :incremental :in :cl-codegraph
  :description "Incremental rebuild and change tracking")

(in-suite :incremental)

(test refresh-returns-diff
  "refresh-graph rebuilds and returns a diff of what changed"
  (let ((g (cl-codegraph:build-graph :cg-incr-pkg)))
    ;; Nothing changed — diff should be empty
    (let ((diff (cl-codegraph:refresh-graph g :cg-incr-pkg)))
      (is (= 0 (getf diff :added)))
      (is (= 0 (getf diff :removed))))))

(test refresh-detects-new-function
  "refresh-graph detects when a new function is added"
  (let ((g (cl-codegraph:build-graph :cg-incr-pkg)))
    ;; Simulate adding a function
    (eval '(defun cg-incr-pkg::new-helper () :new))
    (export (intern "NEW-HELPER" :cg-incr-pkg) :cg-incr-pkg)
    (let ((diff (cl-codegraph:refresh-graph g :cg-incr-pkg)))
      (is (< 0 (getf diff :added))))
    ;; Clean up
    (unintern (intern "NEW-HELPER" :cg-incr-pkg) :cg-incr-pkg)))
