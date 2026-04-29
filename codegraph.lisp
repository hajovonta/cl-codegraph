;;;; codegraph.lisp — Build a Knowledge Graph from a live CL package

(in-package #:cl-codegraph)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-introspect))

;;; Predicates

(defconstant +type+ "rdf:type")
(defconstant +calls+ "cg:calls")
(defconstant +called-by+ "cg:calledBy")
(defconstant +subclass-of+ "cg:subclassOf")
(defconstant +has-slot+ "cg:hasSlot")
(defconstant +method-of+ "cg:methodOf")
(defconstant +specializes-on+ "cg:specializesOn")
(defconstant +exports+ "cg:exports")
(defconstant +in-package+ "cg:inPackage")

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

(defun build-graph (package-designator &key (graph-name nil))
  "Build and return an Ariadne graph representing the code structure of PACKAGE-DESIGNATOR."
  (let ((pkg (find-package package-designator)))
    (when (null pkg)
      (error "Package ~A not found" package-designator))
    (let* ((name (or graph-name (format nil "codegraph/~(~A~)" (package-name pkg))))
           (g (ariadne:make-graph :name name)))
      (index-package g pkg)
      g)))

(defun rebuild-graph (graph package-designator)
  "Clear GRAPH and rebuild it from PACKAGE-DESIGNATOR."
  (let ((pkg (find-package package-designator)))
    (when (null pkg)
      (error "Package ~A not found" package-designator))
    (ariadne:clear-graph graph)
    (index-package graph pkg)
    graph))

;;; Internal indexing

(defun index-package (graph pkg)
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
    ;; Call relationships (separate pass — needs all symbols indexed first)
    (index-call-graph graph exported-symbols)))

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

(defun index-call-graph (graph exported-symbols)
  "Add cg:calls and cg:calledBy triples among EXPORTED-SYMBOLS.
Uses sb-introspect:who-calls: for each exported callee, find which exported symbols call it."
  (let ((sym-set (make-hash-table :test 'eq)))
    ;; Build lookup set
    (dolist (sym exported-symbols)
      (setf (gethash sym sym-set) t))
    ;; For each callable exported symbol, find its callers within the set
    (dolist (callee exported-symbols)
      (when (fboundp callee)
        (let ((callee-uri (symbol-uri callee)))
          (dolist (entry (sb-introspect:who-calls callee))
            (let ((caller (car entry)))
              (when (and (symbolp caller)
                         (gethash caller sym-set)
                         (not (eq caller callee)))
                (let ((caller-uri (symbol-uri caller)))
                  (ariadne:add-triple graph caller-uri +calls+ callee-uri)
                  (ariadne:add-triple graph callee-uri +called-by+ caller-uri))))))))))
