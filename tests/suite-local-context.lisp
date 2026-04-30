;;;; tests/suite-local-context.lisp — Local variable context from source

(in-package #:cl-codegraph-tests)

(def-suite :local-context :in :cl-codegraph
  :description "Local variable context from source walking")

(in-suite :local-context)

;; We'll use a test file with known structure
(defvar *test-source*
  "(in-package #:test-pkg)

(defun compute (x y)
  (let ((sum (+ x y))
        (diff (- x y)))
    (* sum diff)))
")

(test find-defun-parameter
  "Identifies a defun parameter"
  (let ((ctx (cl-codegraph:local-context *test-source* 4 7 "x")))
    (is (not (null ctx)))
    (is (equal (getf ctx :kind) "parameter"))
    (is (equal (getf ctx :function) "compute"))))

(test find-let-binding
  "Identifies a let-bound variable with its value form"
  (let ((ctx (cl-codegraph:local-context *test-source* 6 8 "sum")))
    (is (not (null ctx)))
    (is (equal (getf ctx :kind) "let binding"))
    (is (equal (getf ctx :function) "compute"))
    (is (equal (getf ctx :value-form) "(+ X Y)"))))

(test returns-nil-for-non-local
  "Returns nil for a symbol that isn't locally bound"
  (let ((ctx (cl-codegraph:local-context *test-source* 4 1 "format")))
    (is (null ctx))))
