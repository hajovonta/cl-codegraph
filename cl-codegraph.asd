(defsystem #:cl-codegraph
  :description "Automatic Knowledge Graph of Common Lisp code via introspection"
  :version "0.1.0"
  :depends-on (#:ariadne)
  :serial t
  :components ((:file "package")
               (:file "codegraph")
               (:file "queries")
               (:file "monitor")))
