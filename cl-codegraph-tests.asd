(defsystem #:cl-codegraph-tests
  :depends-on (#:cl-codegraph #:fiveam)
  :serial t
  :components ((:module "tests"
                :components ((:file "package")
                             (:file "suite-core")))))
