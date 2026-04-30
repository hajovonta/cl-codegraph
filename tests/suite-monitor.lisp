;;;; tests/suite-monitor.lisp — Live monitoring with per-symbol dirty tracking

(in-package #:cl-codegraph-tests)

(defpackage #:cg-monitor-pkg
  (:use #:cl)
  (:export #:mon-fn-a #:mon-fn-b))

(in-package #:cg-monitor-pkg)
(defun mon-fn-b () :original)
(defun mon-fn-a () (mon-fn-b))

(in-package #:cl-codegraph-tests)

(def-suite :monitor :in :cl-codegraph
  :description "Live monitoring with incremental updates")

(in-suite :monitor)

(test monitor-creates-graph
  "monitor returns a graph and registers the package"
  (let ((g (cl-codegraph:monitor :cg-monitor-pkg)))
    (unwind-protect
         (progn
           (is (ariadne:graphp g))
           (is (ariadne:has-triple-p g "cg-monitor-pkg:mon-fn-a" "rdf:type" "function")))
      (cl-codegraph:unmonitor :cg-monitor-pkg))))

(test graph-returns-monitored-graph
  "graph retrieves the monitored graph for a package"
  (cl-codegraph:monitor :cg-monitor-pkg)
  (unwind-protect
       (is (ariadne:graphp (cl-codegraph:graph :cg-monitor-pkg)))
    (cl-codegraph:unmonitor :cg-monitor-pkg)))

(test redefine-marks-dirty-and-updates-on-query
  "Redefining a function updates the graph on next query"
  (cl-codegraph:monitor :cg-monitor-pkg)
  (unwind-protect
       (progn
         ;; Redefine mon-fn-a to call nothing
         (eval '(defun cg-monitor-pkg:mon-fn-a () :changed))
         ;; Graph should update on access
         (let ((g (cl-codegraph:graph :cg-monitor-pkg)))
           ;; The old call edge should be gone
           (is (not (ariadne:has-triple-p g "cg-monitor-pkg:mon-fn-a" "cg:calls" "cg-monitor-pkg:mon-fn-b")))))
    ;; Restore and cleanup
    (eval '(defun cg-monitor-pkg:mon-fn-a () (cg-monitor-pkg:mon-fn-b)))
    (cl-codegraph:unmonitor :cg-monitor-pkg)))

(test unmonitor-removes-hook
  "unmonitor stops tracking the package"
  (cl-codegraph:monitor :cg-monitor-pkg)
  (cl-codegraph:unmonitor :cg-monitor-pkg)
  (is (null (cl-codegraph:graph :cg-monitor-pkg))))
