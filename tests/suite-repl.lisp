;;;; tests/suite-repl.lisp — REPL-friendly output formatting

(in-package #:cl-codegraph-tests)

(def-suite :repl :in :cl-codegraph
  :description "REPL-friendly output formatting")

(in-suite :repl)

(test describe-symbol-returns-string
  "describe-symbol returns a formatted string about a symbol"
  (let* ((g (cl-codegraph:build-graph :cg-call-pkg))
         (desc (cl-codegraph:describe-symbol g "cg-call-pkg:caller-fn")))
    (is (stringp desc))
    (is (search "caller-fn" desc))
    (is (search "function" desc))
    (is (search "calls" desc))))

(test describe-symbol-shows-callers-and-callees
  "describe-symbol shows both what it calls and who calls it"
  (let* ((g (cl-codegraph:build-graph :cg-call-pkg))
         (desc (cl-codegraph:describe-symbol g "cg-call-pkg:intermediate-fn")))
    ;; calls callee-fn
    (is (search "callee-fn" desc))
    ;; called by caller-fn
    (is (search "caller-fn" desc))))

(test summary-returns-overview
  "summary returns a formatted overview of the graph"
  (let* ((g (cl-codegraph:build-graph :cg-call-pkg))
         (s (cl-codegraph:summary g)))
    (is (stringp s))
    (is (search "function" s))
    (is (search "call" s))))
