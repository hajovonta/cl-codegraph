(defsystem #:cl-codegraph-tests
  :depends-on (#:cl-codegraph #:fiveam)
  :serial t
  :components ((:module "tests"
                :components ((:file "package")
                             (:file "suite-core")
                             (:file "suite-calls")
                             (:file "suite-cross-package")
                             (:file "suite-metadata")
                             (:file "suite-macro-var-deps")
                             (:file "suite-query-helpers")
                             (:file "suite-internal")))))
