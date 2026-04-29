;;;; tests/suite-cross-package.lisp — Cross-package dependency tracking

(in-package #:cl-codegraph-tests)

;;; Two packages where one calls into the other

(defpackage #:cg-dep-base
  (:use #:cl)
  (:export #:base-fn #:base-helper))

(in-package #:cg-dep-base)
(defun base-helper (x) (* x x))
(defun base-fn (x) (base-helper x))

(defpackage #:cg-dep-consumer
  (:use #:cl)
  (:export #:consumer-fn #:internal-fn))

(in-package #:cg-dep-consumer)
(defun internal-fn (x) (1+ x))
(defun consumer-fn (x) (cg-dep-base:base-fn (internal-fn x)))

(in-package #:cl-codegraph-tests)

(def-suite :cross-package :in :cl-codegraph
  :description "Cross-package call dependency tracking")

(in-suite :cross-package)

(test cross-package-calls-detected
  "Calls to functions in other packages are recorded"
  (let ((g (cl-codegraph:build-graph :cg-dep-consumer :include-external-calls t)))
    (is (has-triple-p g "cg-dep-consumer:consumer-fn" "cg:calls" "cg-dep-base:base-fn"))))

(test cross-package-callee-typed
  "External callees get a type triple even though they're not in the target package"
  (let ((g (cl-codegraph:build-graph :cg-dep-consumer :include-external-calls t)))
    (is (has-triple-p g "cg-dep-base:base-fn" "rdf:type" "function"))))

(test cross-package-callee-marked-external
  "External callees are marked as external"
  (let ((g (cl-codegraph:build-graph :cg-dep-consumer :include-external-calls t)))
    (is (has-triple-p g "cg-dep-base:base-fn" "cg:external" "true"))))

(test internal-calls-still-work
  "Intra-package calls still recorded alongside cross-package ones"
  (let ((g (cl-codegraph:build-graph :cg-dep-consumer :include-external-calls t)))
    (is (has-triple-p g "cg-dep-consumer:consumer-fn" "cg:calls" "cg-dep-consumer:internal-fn"))))

(test without-flag-no-external-calls
  "Without :include-external-calls, only intra-package calls appear"
  (let ((g (cl-codegraph:build-graph :cg-dep-consumer)))
    (is (not (has-triple-p g "cg-dep-consumer:consumer-fn" "cg:calls" "cg-dep-base:base-fn")))
    (is (has-triple-p g "cg-dep-consumer:consumer-fn" "cg:calls" "cg-dep-consumer:internal-fn"))))

(test depends-on-package-triple
  "Package-level dependency is recorded"
  (let ((g (cl-codegraph:build-graph :cg-dep-consumer :include-external-calls t)))
    (is (has-triple-p g "pkg:cg-dep-consumer" "cg:dependsOn" "pkg:cg-dep-base"))))
