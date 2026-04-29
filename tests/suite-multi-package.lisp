;;;; tests/suite-multi-package.lisp — Multi-package and ASDF system graphs

(in-package #:cl-codegraph-tests)

(def-suite :multi-package :in :cl-codegraph
  :description "Multi-package and ASDF system graph building")

(in-suite :multi-package)

(test build-multi-graph-combines-packages
  "build-multi-graph indexes multiple packages into one graph"
  (let ((g (cl-codegraph:build-multi-graph '(:cg-call-pkg :cg-test-pkg))))
    (is (ariadne:graphp g))
    ;; Has symbols from both packages
    (is (ariadne:has-triple-p g "cg-call-pkg:caller-fn" "rdf:type" "function"))
    (is (ariadne:has-triple-p g "cg-test-pkg:test-function" "rdf:type" "function"))))

(test build-multi-graph-cross-package-calls
  "Cross-package calls between listed packages are captured"
  (let ((g (cl-codegraph:build-multi-graph '(:cg-dep-base :cg-dep-consumer))))
    ;; consumer-fn calls base-fn across packages
    (is (ariadne:has-triple-p g "cg-dep-consumer:consumer-fn" "cg:calls" "cg-dep-base:base-fn"))))

(test build-system-graph-works
  "build-system-graph indexes all packages of an ASDF system"
  ;; cl-codegraph itself is a small system we can test against
  (let ((g (cl-codegraph:build-system-graph :cl-codegraph)))
    (is (ariadne:graphp g))
    (is (ariadne:has-triple-p g "cl-codegraph:build-graph" "rdf:type" "function"))))

(test multi-graph-has-package-nodes
  "Each package gets its own node in the graph"
  (let ((g (cl-codegraph:build-multi-graph '(:cg-call-pkg :cg-test-pkg))))
    (is (ariadne:has-triple-p g "pkg:cg-call-pkg" "cg:exports" "cg-call-pkg:caller-fn"))
    (is (ariadne:has-triple-p g "pkg:cg-test-pkg" "cg:exports" "cg-test-pkg:test-function"))))
