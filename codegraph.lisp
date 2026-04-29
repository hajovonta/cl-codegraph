;;;; codegraph.lisp — Build a Knowledge Graph from a live CL package

(in-package #:cl-codegraph)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-introspect))

(defmacro define-constant (name value)
  `(defconstant ,name (if (boundp ',name) (symbol-value ',name) ,value)))

;;; Predicates

(define-constant +type+ "rdf:type")
(define-constant +calls+ "cg:calls")
(define-constant +called-by+ "cg:calledBy")
(define-constant +subclass-of+ "cg:subclassOf")
(define-constant +has-slot+ "cg:hasSlot")
(define-constant +method-of+ "cg:methodOf")
(define-constant +specializes-on+ "cg:specializesOn")
(define-constant +exports+ "cg:exports")
(define-constant +in-package+ "cg:inPackage")
(define-constant +external+ "cg:external")
(define-constant +depends-on+ "cg:dependsOn")

;;; Symbol classification

(defun classify-symbol (sym)
  "Return a keyword classifying SYM."
  (cond
    ((find-class sym nil) :class)
    ((and (fboundp sym)
          (typep (fdefinition sym) 'generic-function))
     :generic-function)
    ((macro-function sym) :macro)
    ((fboundp sym) :function)
    ((constantp sym) :constant)
    ((boundp sym) :special-variable)
    (t :other)))

;;; Node naming

(defun symbol-uri (sym)
  "Return a string URI for SYM."
  (format nil "~(~A:~A~)" (package-name (symbol-package sym)) (symbol-name sym)))

;;; Graph building

(defun build-graph (package-designator &key (graph-name nil) (include-external-calls nil))
  "Build and return an Ariadne graph representing the code structure of PACKAGE-DESIGNATOR.
When INCLUDE-EXTERNAL-CALLS is true, also record calls to functions in other packages."
  (let ((pkg (find-package package-designator)))
    (when (null pkg)
      (error "Package ~A not found" package-designator))
    (let* ((name (or graph-name (format nil "codegraph/~(~A~)" (package-name pkg))))
           (g (ariadne:make-graph :name name)))
      (index-package g pkg include-external-calls)
      g)))

(defun rebuild-graph (graph package-designator &key (include-external-calls nil))
  "Clear GRAPH and rebuild it from PACKAGE-DESIGNATOR."
  (let ((pkg (find-package package-designator)))
    (when (null pkg)
      (error "Package ~A not found" package-designator))
    (ariadne:clear-graph graph)
    (index-package graph pkg include-external-calls)
    graph))

;;; Internal indexing

(defun index-package (graph pkg include-external-calls)
  "Walk all exported symbols of PKG and add triples to GRAPH."
  (let ((pkg-uri (format nil "pkg:~(~A~)" (package-name pkg)))
        (exported-symbols '()))
    (do-external-symbols (sym pkg)
      (push sym exported-symbols))
    ;; Index each symbol
    (dolist (sym exported-symbols)
      (let ((uri (symbol-uri sym))
            (kind (classify-symbol sym)))
        (ariadne:add-triple graph uri +type+ (string-downcase (symbol-name kind)))
        (ariadne:add-triple graph uri +in-package+ pkg-uri)
        (ariadne:add-triple graph pkg-uri +exports+ uri)
        (case kind
          (:class (index-class graph sym uri))
          (:generic-function (index-generic graph sym uri)))))
    ;; Call relationships
    (index-call-graph graph exported-symbols pkg include-external-calls)))

(defun index-class (graph sym uri)
  "Add class hierarchy and slot triples for class named by SYM."
  (let ((class (find-class sym)))
    (dolist (super (sb-mop:class-direct-superclasses class))
      (let ((super-name (class-name super)))
        (unless (member super-name '(t standard-object))
          (ariadne:add-triple graph uri +subclass-of+ (symbol-uri super-name)))))
    (dolist (slot (sb-mop:class-direct-slots class))
      (let ((slot-name (sb-mop:slot-definition-name slot)))
        (ariadne:add-triple graph uri +has-slot+
                            (format nil "~A.~(~A~)" uri (symbol-name slot-name)))))))

(defun index-generic (graph sym uri)
  "Add method and specializer triples for generic function SYM."
  (let ((gf (fdefinition sym)))
    (dolist (method (sb-mop:generic-function-methods gf))
      (let* ((specializers (sb-mop:method-specializers method))
             (method-uri (format nil "~A/method~{/~(~A~)~}"
                                 uri
                                 (mapcar (lambda (s)
                                           (if (typep s 'sb-mop:eql-specializer)
                                               (format nil "eql-~A" (sb-mop:eql-specializer-object s))
                                               (symbol-name (class-name s))))
                                         specializers))))
        (ariadne:add-triple graph method-uri +method-of+ uri)
        (dolist (spec specializers)
          (when (typep spec 'class)
            (let ((spec-name (class-name spec)))
              (unless (eq spec-name t)
                (ariadne:add-triple graph method-uri +specializes-on+
                                    (symbol-uri spec-name))))))))))

(defun function-name-of (fn)
  "Get the symbol name of a function object, or nil."
  (nth-value 2 (function-lambda-expression fn)))

(defun index-call-graph (graph exported-symbols pkg include-external-calls)
  "Add cg:calls and cg:calledBy triples using find-function-callees (forward index)."
  (let ((sym-set (make-hash-table :test 'eq))
        (pkg-uri (format nil "pkg:~(~A~)" (package-name pkg)))
        (dep-packages (make-hash-table :test 'equal)))
    (dolist (sym exported-symbols)
      (setf (gethash sym sym-set) t))
    ;; For each exported callable symbol, find what it calls
    (dolist (caller exported-symbols)
      (when (fboundp caller)
        (let ((caller-uri (symbol-uri caller))
              (callees (ignore-errors
                        (sb-introspect:find-function-callees (fdefinition caller)))))
          (dolist (callee-fn callees)
            (let ((callee-name (function-name-of callee-fn)))
              (when (and (symbolp callee-name) (symbol-package callee-name))
                (cond
                  ;; Intra-package call
                  ((gethash callee-name sym-set)
                   (unless (eq callee-name caller)
                     (let ((callee-uri (symbol-uri callee-name)))
                       (ariadne:add-triple graph caller-uri +calls+ callee-uri)
                       (ariadne:add-triple graph callee-uri +called-by+ caller-uri))))
                  ;; Cross-package call
                  ((and include-external-calls
                        (not (eq (symbol-package callee-name) (find-package :cl))))
                   (let ((callee-uri (symbol-uri callee-name))
                         (ext-pkg-uri (format nil "pkg:~(~A~)"
                                             (package-name (symbol-package callee-name)))))
                     (ariadne:add-triple graph caller-uri +calls+ callee-uri)
                     (ariadne:add-triple graph callee-uri +called-by+ caller-uri)
                     (ariadne:add-triple graph callee-uri +type+
                                         (string-downcase (symbol-name (classify-symbol callee-name))))
                     (ariadne:add-triple graph callee-uri +external+ "true")
                     (setf (gethash ext-pkg-uri dep-packages) t))))))))))
    ;; Record package-level dependencies
    (when include-external-calls
      (maphash (lambda (ext-pkg-uri _)
                 (declare (ignore _))
                 (ariadne:add-triple graph pkg-uri +depends-on+ ext-pkg-uri))
               dep-packages))))
