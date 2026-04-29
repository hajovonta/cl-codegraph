;;;; tests/suite-core.lisp — Symbol classification and basic graph structure

(in-package #:cl-codegraph-tests)

(in-suite :cl-codegraph)

;;; A test package with known symbols of each kind

(defpackage #:cg-test-pkg
  (:use #:cl)
  (:export #:test-function
           #:test-macro
           #:test-generic
           #:test-class
           #:test-subclass
           #:+test-constant+
           #:*test-variable*))

(in-package #:cg-test-pkg)

(defun test-function (x) (1+ x))
(defmacro test-macro (form) `(progn ,form))
(defgeneric test-generic (obj))
(defclass test-class ()
  ((name :initarg :name)
   (value :initarg :value)))
(defclass test-subclass (test-class)
  ((extra :initarg :extra)))
(defconstant +test-constant+ 42)
(defvar *test-variable* "hello")

;; A method on the generic
(defmethod test-generic ((obj test-class))
  (slot-value obj 'name))

(in-package #:cl-codegraph-tests)

;;; Helper to query triples easily

(defun has-triple-p (graph subj pred obj)
  (ariadne:has-triple-p graph subj pred obj))

(defun triples-with (graph &key subject predicate object)
  (ariadne:get-triples graph
                       :subject subject
                       :predicate predicate
                       :object object))

;;; Tests

(def-suite :symbol-classification :in :cl-codegraph
  :description "Symbol classification and type triples")

(in-suite :symbol-classification)

(def-fixture test-graph ()
  (let ((*graph* (cl-codegraph:build-graph :cg-test-pkg)))
    (&body)))

(defvar *graph* nil)

(test build-graph-returns-graph
  "build-graph returns an Ariadne graph"
  (let ((g (cl-codegraph:build-graph :cg-test-pkg)))
    (is (ariadne:graphp g))
    (is (< 0 (ariadne:triple-count g)))))

(test function-classified-correctly
  "Regular functions get type 'function'"
  (let ((g (cl-codegraph:build-graph :cg-test-pkg)))
    (is (has-triple-p g "cg-test-pkg:test-function" "rdf:type" "function"))))

(test macro-classified-correctly
  "Macros get type 'macro'"
  (let ((g (cl-codegraph:build-graph :cg-test-pkg)))
    (is (has-triple-p g "cg-test-pkg:test-macro" "rdf:type" "macro"))))

(test generic-classified-correctly
  "Generic functions get type 'generic-function'"
  (let ((g (cl-codegraph:build-graph :cg-test-pkg)))
    (is (has-triple-p g "cg-test-pkg:test-generic" "rdf:type" "generic-function"))))

(test class-classified-correctly
  "Classes get type 'class'"
  (let ((g (cl-codegraph:build-graph :cg-test-pkg)))
    (is (has-triple-p g "cg-test-pkg:test-class" "rdf:type" "class"))))

(test constant-classified-correctly
  "Constants get type 'constant'"
  (let ((g (cl-codegraph:build-graph :cg-test-pkg)))
    (is (has-triple-p g "cg-test-pkg:+test-constant+" "rdf:type" "constant"))))

(test special-variable-classified-correctly
  "Special variables get type 'special-variable'"
  (let ((g (cl-codegraph:build-graph :cg-test-pkg)))
    (is (has-triple-p g "cg-test-pkg:*test-variable*" "rdf:type" "special-variable"))))

(test all-symbols-have-package-membership
  "Every exported symbol has an inPackage triple"
  (let ((g (cl-codegraph:build-graph :cg-test-pkg)))
    (is (has-triple-p g "cg-test-pkg:test-function" "cg:inPackage" "pkg:cg-test-pkg"))
    (is (has-triple-p g "cg-test-pkg:test-class" "cg:inPackage" "pkg:cg-test-pkg"))
    (is (has-triple-p g "cg-test-pkg:+test-constant+" "cg:inPackage" "pkg:cg-test-pkg"))))

(test package-exports-symbols
  "Package node has exports triples for each symbol"
  (let ((g (cl-codegraph:build-graph :cg-test-pkg)))
    (is (has-triple-p g "pkg:cg-test-pkg" "cg:exports" "cg-test-pkg:test-function"))
    (is (has-triple-p g "pkg:cg-test-pkg" "cg:exports" "cg-test-pkg:test-class"))))

(test class-hierarchy
  "Subclass relationships are recorded"
  (let ((g (cl-codegraph:build-graph :cg-test-pkg)))
    (is (has-triple-p g "cg-test-pkg:test-subclass" "cg:subclassOf" "cg-test-pkg:test-class"))))

(test class-slots
  "Direct slots are recorded"
  (let ((g (cl-codegraph:build-graph :cg-test-pkg)))
    (is (has-triple-p g "cg-test-pkg:test-class" "cg:hasSlot" "cg-test-pkg:test-class.name"))
    (is (has-triple-p g "cg-test-pkg:test-class" "cg:hasSlot" "cg-test-pkg:test-class.value"))))

(test generic-has-methods
  "Methods are linked to their generic function"
  (let ((g (cl-codegraph:build-graph :cg-test-pkg)))
    (let ((methods (triples-with g :predicate "cg:methodOf")))
      (is (< 0 (length methods)))
      ;; At least one method points to test-generic
      (is (some (lambda (tr)
                  (string= (ariadne:triple-object tr) "cg-test-pkg:test-generic"))
                methods)))))

(test method-specializes-on-class
  "Methods record their specializer classes"
  (let ((g (cl-codegraph:build-graph :cg-test-pkg)))
    (let ((specs (triples-with g :predicate "cg:specializesOn")))
      (is (< 0 (length specs)))
      (is (some (lambda (tr)
                  (string= (ariadne:triple-object tr) "cg-test-pkg:test-class"))
                specs)))))

(test rebuild-graph-clears-and-repopulates
  "rebuild-graph produces a fresh graph with same content"
  (let ((g (cl-codegraph:build-graph :cg-test-pkg)))
    (let ((count-before (ariadne:triple-count g)))
      (cl-codegraph:rebuild-graph g :cg-test-pkg)
      (is (= count-before (ariadne:triple-count g))))))

(test nonexistent-package-signals-error
  "build-graph signals an error for unknown packages"
  (signals error (cl-codegraph:build-graph :no-such-package-xyz)))
