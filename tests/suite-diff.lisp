;;;; tests/suite-diff.lisp — Graph diff / change detection

(in-package #:cl-codegraph-tests)

(defpackage #:cg-diff-pkg
  (:use #:cl)
  (:export #:stable-fn #:changing-fn))

(in-package #:cg-diff-pkg)
(defun stable-fn () :stable)
(defun changing-fn (x) (stable-fn) x)

(in-package #:cl-codegraph-tests)

(def-suite :diff :in :cl-codegraph
  :description "Graph diff and change detection")

(in-suite :diff)

(test diff-identical-graphs-empty
  "Diffing a graph against itself produces no changes"
  (let* ((g (cl-codegraph:build-graph :cg-diff-pkg))
         (diff (cl-codegraph:diff-graphs g g)))
    (is (null (getf diff :added)))
    (is (null (getf diff :removed)))))

(test diff-detects-added-triples
  "New triples in the second graph appear in :added"
  (let ((g1 (cl-codegraph:build-graph :cg-diff-pkg))
        (g2 (cl-codegraph:build-graph :cg-diff-pkg)))
    ;; Simulate a change: add a triple to g2
    (ariadne:add-triple g2 "cg-diff-pkg:new-fn" "rdf:type" "function")
    (let ((diff (cl-codegraph:diff-graphs g1 g2)))
      (is (= 1 (length (getf diff :added))))
      (is (null (getf diff :removed))))))

(test diff-detects-removed-triples
  "Triples missing from the second graph appear in :removed"
  (let ((g1 (cl-codegraph:build-graph :cg-diff-pkg))
        (g2 (cl-codegraph:build-graph :cg-diff-pkg)))
    (ariadne:add-triple g1 "cg-diff-pkg:old-fn" "rdf:type" "function")
    (let ((diff (cl-codegraph:diff-graphs g1 g2)))
      (is (null (getf diff :added)))
      (is (= 1 (length (getf diff :removed)))))))

(test diff-summary-reports-counts
  "diff-summary returns a human-readable plist of change counts"
  (let ((g1 (cl-codegraph:build-graph :cg-diff-pkg))
        (g2 (cl-codegraph:build-graph :cg-diff-pkg)))
    (ariadne:add-triple g2 "cg-diff-pkg:new-fn" "rdf:type" "function")
    (ariadne:add-triple g2 "cg-diff-pkg:new-fn" "cg:calls" "cg-diff-pkg:stable-fn")
    (let ((summary (cl-codegraph:diff-summary g1 g2)))
      (is (= 2 (getf summary :added)))
      (is (= 0 (getf summary :removed))))))
