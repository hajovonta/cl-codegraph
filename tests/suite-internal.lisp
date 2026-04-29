;;;; tests/suite-internal.lisp — Include internal (non-exported) symbols

(in-package #:cl-codegraph-tests)

(defpackage #:cg-internal-pkg
  (:use #:cl)
  (:export #:public-fn))

(in-package #:cg-internal-pkg)

(defun helper (x) (1+ x))
(defun public-fn (x) (helper x))

(in-package #:cl-codegraph-tests)

(def-suite :include-internal :in :cl-codegraph
  :description "Include internal symbols in the graph")

(in-suite :include-internal)

(test internal-symbols-excluded-by-default
  "By default, internal symbols are not in the graph"
  (let ((g (cl-codegraph:build-graph :cg-internal-pkg)))
    (is (not (has-triple-p g "cg-internal-pkg::helper" "rdf:type" "function")))))

(test internal-symbols-included-with-flag
  "With :include-internal t, internal symbols appear"
  (let ((g (cl-codegraph:build-graph :cg-internal-pkg :include-internal t)))
    (is (has-triple-p g "cg-internal-pkg::helper" "rdf:type" "function"))))

(test internal-call-chain-visible
  "Internal symbols complete the call chain"
  (let ((g (cl-codegraph:build-graph :cg-internal-pkg :include-internal t)))
    (is (has-triple-p g "cg-internal-pkg:public-fn" "cg:calls" "cg-internal-pkg::helper"))))

(test internal-symbols-marked
  "Internal symbols get a cg:internal marker"
  (let ((g (cl-codegraph:build-graph :cg-internal-pkg :include-internal t)))
    (is (has-triple-p g "cg-internal-pkg::helper" "cg:internal" "true"))))

(test call-chain-through-internals
  "call-chain works through internal symbols"
  (let ((g (cl-codegraph:build-graph :cg-internal-pkg :include-internal t)))
    (let ((chain (cl-codegraph:call-chain g "cg-internal-pkg:public-fn"
                                            "cg-internal-pkg::helper")))
      (is (equal chain '("cg-internal-pkg:public-fn" "cg-internal-pkg::helper"))))))
