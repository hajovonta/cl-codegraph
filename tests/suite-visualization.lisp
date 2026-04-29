;;;; tests/suite-visualization.lisp — Graphviz export and subgraph extraction

(in-package #:cl-codegraph-tests)

(def-suite :visualization :in :cl-codegraph
  :description "Graphviz export and subgraph extraction")

(in-suite :visualization)

(test export-dot-produces-output
  "export-dot returns a non-empty DOT string"
  (let* ((g (cl-codegraph:build-graph :cg-call-pkg))
         (dot (cl-codegraph:export-dot g)))
    (is (stringp dot))
    (is (search "digraph" dot))
    (is (search "cg-call-pkg:caller-fn" dot))))

(test export-dot-with-predicate-filter
  "export-dot can filter to only show call edges"
  (let* ((g (cl-codegraph:build-graph :cg-call-pkg))
         (dot (cl-codegraph:export-dot g :predicates '("cg:calls"))))
    (is (search "cg-call-pkg:caller-fn" dot))
    ;; Should not contain type edges
    (is (not (search "rdf:type" dot)))))

(test neighborhood-returns-subgraph
  "neighborhood extracts triples within N hops of a symbol"
  (let* ((g (cl-codegraph:build-graph :cg-call-pkg))
         (sub (cl-codegraph:neighborhood g "cg-call-pkg:intermediate-fn" :depth 1)))
    ;; Should contain intermediate-fn's direct connections
    (is (ariadne:graphp sub))
    (is (< 0 (ariadne:triple-count sub)))
    ;; caller-fn calls intermediate-fn (1 hop)
    (is (ariadne:has-triple-p sub "cg-call-pkg:caller-fn" "cg:calls" "cg-call-pkg:intermediate-fn"))
    ;; intermediate-fn calls callee-fn (1 hop)
    (is (ariadne:has-triple-p sub "cg-call-pkg:intermediate-fn" "cg:calls" "cg-call-pkg:callee-fn"))))

(test neighborhood-respects-depth
  "neighborhood at depth 0 returns only the node's own triples"
  (let* ((g (cl-codegraph:build-graph :cg-call-pkg))
         (sub (cl-codegraph:neighborhood g "cg-call-pkg:intermediate-fn" :depth 0)))
    ;; Should have triples where intermediate-fn is subject or object
    (is (< 0 (ariadne:triple-count sub)))
    ;; But NOT caller-fn -> callee-fn (that's 2 hops away)
    (is (not (ariadne:has-triple-p sub "cg-call-pkg:caller-fn" "cg:calls" "cg-call-pkg:callee-fn")))))
