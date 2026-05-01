;;;; tests/suite-web-viewer.lisp — Web visualization via Ariadne's Cytoscape.js

(in-package #:cl-codegraph-tests)

(def-suite :web-viewer :in :cl-codegraph
  :description "Web visualization integration")

(in-suite :web-viewer)

(test start-viewer-returns-url
  "start-viewer starts the web server and returns a URL"
  (let ((url (cl-codegraph:start-viewer :cg-call-pkg)))
    (unwind-protect
         (progn
           (is (stringp url))
           (is (search "http" url)))
      (cl-codegraph:stop-viewer))))

(test start-viewer-with-predicates
  "start-viewer accepts predicate filter"
  (let ((url (cl-codegraph:start-viewer :cg-call-pkg :predicates '("cg:calls"))))
    (unwind-protect
         (is (stringp url))
      (cl-codegraph:stop-viewer))))
