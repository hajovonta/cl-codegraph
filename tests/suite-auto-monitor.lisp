;;;; tests/suite-auto-monitor.lisp — Auto-monitor on first access

(in-package #:cl-codegraph-tests)

(def-suite :auto-monitor :in :cl-codegraph
  :description "Auto-monitor packages on first access")

(in-suite :auto-monitor)

(test ensure-monitor-creates-graph
  "ensure-monitor monitors a package if not already monitored"
  (cl-codegraph:ensure-monitor :cg-call-pkg)
  (unwind-protect
       (progn
         (is (ariadne:graphp (cl-codegraph:graph :cg-call-pkg)))
         (is (ariadne:has-triple-p (cl-codegraph:graph :cg-call-pkg)
                                   "cg-call-pkg:caller-fn" "rdf:type" "function")))
    (cl-codegraph:unmonitor :cg-call-pkg)))

(test ensure-monitor-idempotent
  "ensure-monitor does nothing if already monitored"
  (cl-codegraph:monitor :cg-call-pkg)
  (unwind-protect
       (let ((g1 (cl-codegraph:graph :cg-call-pkg)))
         (cl-codegraph:ensure-monitor :cg-call-pkg)
         ;; Same graph object
         (is (eq g1 (cl-codegraph:graph :cg-call-pkg))))
    (cl-codegraph:unmonitor :cg-call-pkg)))

(test describe-symbol-auto-monitors
  "describe-symbol-live auto-monitors and returns info"
  (unwind-protect
       (let ((result (cl-codegraph:describe-symbol-live :cg-call-pkg "cg-call-pkg:caller-fn")))
         (is (stringp result))
         (is (search "function" result)))
    (cl-codegraph:unmonitor :cg-call-pkg)))
