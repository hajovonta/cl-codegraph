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
(define-constant +lambda-list+ "cg:lambdaList")
(define-constant +docstring+ "cg:docstring")
(define-constant +source-file+ "cg:sourceFile")
(define-constant +expands-macro+ "cg:expandsMacro")
(define-constant +reads-var+ "cg:readsVar")
(define-constant +writes-var+ "cg:writesVar")

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
  "Return a string URI for SYM. Uses :: for internal symbols, : for external."
  (let* ((pkg (symbol-package sym))
         (sep (if (eq (nth-value 1 (find-symbol (symbol-name sym) pkg)) :external)
                  ":" "::")))
    (format nil "~(~A~A~A~)" (package-name pkg) sep (symbol-name sym))))

;;; Graph building

(defun build-graph (package-designator &key graph-name include-external-calls include-internal)
  "Build and return an Ariadne graph representing the code structure of PACKAGE-DESIGNATOR."
  (let ((pkg (find-package package-designator)))
    (when (null pkg)
      (error "Package ~A not found" package-designator))
    (let* ((name (or graph-name (format nil "codegraph/~(~A~)" (package-name pkg))))
           (g (ariadne:make-graph :name name)))
      (index-package g pkg include-external-calls include-internal)
      g)))

(defun rebuild-graph (graph package-designator &key include-external-calls include-internal)
  "Clear GRAPH and rebuild it from PACKAGE-DESIGNATOR."
  (let ((pkg (find-package package-designator)))
    (when (null pkg)
      (error "Package ~A not found" package-designator))
    (ariadne:clear-graph graph)
    (index-package graph pkg include-external-calls include-internal)
    graph))

;;; Internal indexing

(defun index-package (graph pkg include-external-calls include-internal)
  "Walk symbols of PKG and add triples to GRAPH."
  (let ((pkg-uri (format nil "pkg:~(~A~)" (package-name pkg)))
        (exported-symbols '())
        (all-symbols '()))
    (do-external-symbols (sym pkg)
      (push sym exported-symbols))
    (if include-internal
        (do-symbols (sym pkg)
          (when (eq (symbol-package sym) pkg)
            (push sym all-symbols)))
        (setf all-symbols exported-symbols))
    ;; Index each symbol
    (dolist (sym all-symbols)
      (let ((uri (symbol-uri sym))
            (kind (classify-symbol sym))
            (externalp (member sym exported-symbols)))
        (ariadne:add-triple graph uri +type+ (string-downcase (symbol-name kind)))
        (ariadne:add-triple graph uri +in-package+ pkg-uri)
        (when externalp
          (ariadne:add-triple graph pkg-uri +exports+ uri))
        (when (and include-internal (not externalp))
          (ariadne:add-triple graph uri "cg:internal" "true"))
        (case kind
          (:class (index-class graph sym uri))
          (:generic-function (index-generic graph sym uri)))
        ;; Metadata
        (index-metadata graph sym uri kind)
        ;; Macro/variable dependencies
        (index-macro-var-deps graph sym uri kind all-symbols)))
    ;; Call relationships
    (index-call-graph graph all-symbols pkg include-external-calls)))

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

(defun index-metadata (graph sym uri kind)
  "Add lambda-list, docstring, and source-file triples for SYM."
  ;; Lambda list (for functions, generics, macros)
  (when (member kind '(:function :generic-function :macro))
    (let ((ll (ignore-errors (sb-introspect:function-lambda-list sym))))
      (when ll
        (ariadne:add-triple graph uri +lambda-list+
                            (string-upcase (princ-to-string ll))))))
  ;; Docstring
  (let ((doc (cond
               ((member kind '(:function :generic-function :macro))
                (documentation sym 'function))
               ((eq kind :class)
                (documentation (find-class sym) t))
               ((member kind '(:special-variable :constant))
                (documentation sym 'variable)))))
    (when doc
      (ariadne:add-triple graph uri +docstring+ doc)))
  ;; Source location
  (let* ((type (case kind
                 ((:function :generic-function) :function)
                 (:macro :function)
                 (:class :class)
                 (:special-variable :variable)
                 (:constant :variable)))
         (sources (when type
                    (ignore-errors
                     (sb-introspect:find-definition-sources-by-name sym type)))))
    (when (and sources (sb-introspect:definition-source-pathname (first sources)))
      (ariadne:add-triple graph uri +source-file+
                          (namestring (sb-introspect:definition-source-pathname (first sources)))))))

(defun index-macro-var-deps (graph sym uri kind exported-symbols)
  "Add macro-expansion and variable read/write dependency triples."
  ;; who-macroexpands: for each exported macro, find which exported fns expand it
  (when (eq kind :macro)
    (dolist (entry (sb-introspect:who-macroexpands sym))
      (let ((user (car entry)))
        (when (and (symbolp user) (member user exported-symbols))
          (ariadne:add-triple graph (symbol-uri user) +expands-macro+ uri)))))
  ;; who-references / who-sets: for exported specials, find readers/writers
  (when (member kind '(:special-variable))
    (dolist (entry (sb-introspect:who-references sym))
      (let ((reader (car entry)))
        (when (and (symbolp reader) (member reader exported-symbols))
          (ariadne:add-triple graph (symbol-uri reader) +reads-var+ uri))))
    (dolist (entry (sb-introspect:who-sets sym))
      (let ((writer (car entry)))
        (when (and (symbolp writer) (member writer exported-symbols))
          (ariadne:add-triple graph (symbol-uri writer) +writes-var+ uri))))))

(defun function-name-of (fn)
  "Get the symbol name of a function object, or nil."
  (when (functionp fn)
    (nth-value 2 (function-lambda-expression fn))))

(defun index-call-graph (graph all-symbols pkg include-external-calls)
  "Add cg:calls and cg:calledBy triples using find-function-callees.
For generic functions, supplements with who-calls on exported symbols only (fast)."
  (let ((sym-set (make-hash-table :test 'eq))
        (pkg-uri (format nil "pkg:~(~A~)" (package-name pkg)))
        (dep-packages (make-hash-table :test 'equal))
        (exported '()))
    (dolist (sym all-symbols)
      (setf (gethash sym sym-set) t))
    (do-external-symbols (sym pkg)
      (push sym exported))
    ;; Forward pass: find-function-callees
    (dolist (caller all-symbols)
      (when (fboundp caller)
        (let ((caller-uri (symbol-uri caller)))
          (dolist (callee-fn (callees-of caller))
            (let ((callee-name (function-name-of callee-fn)))
              (when (and (symbolp callee-name) (symbol-package callee-name))
                (cond
                  ((gethash callee-name sym-set)
                   (unless (eq callee-name caller)
                     (let ((callee-uri (symbol-uri callee-name)))
                       (ariadne:add-triple graph caller-uri +calls+ callee-uri)
                       (ariadne:add-triple graph callee-uri +called-by+ caller-uri))))
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
    (when include-external-calls
      (maphash (lambda (ext-pkg-uri _)
                 (declare (ignore _))
                 (ariadne:add-triple graph pkg-uri +depends-on+ ext-pkg-uri))
               dep-packages))))

(defun callees-of (sym)
  "Return all function objects called by SYM. For GFs, walks method fast-functions."
  (let ((fns '())
        (def (fdefinition sym)))
    (dolist (f (ignore-errors (sb-introspect:find-function-callees def)))
      (push f fns))
    (when (typep def 'generic-function)
      (let ((fast-fn-accessor (find-symbol "SAFE-METHOD-FAST-FUNCTION" :sb-pcl)))
        (when (and fast-fn-accessor (fboundp fast-fn-accessor))
          (dolist (method (sb-mop:generic-function-methods def))
            (let ((fast (ignore-errors (funcall fast-fn-accessor method))))
              (when fast
                (dolist (f (ignore-errors (sb-introspect:find-function-callees fast)))
                  (push f fns))))))))
    fns))

;;; Multi-package

(defun build-multi-graph (package-designators &key graph-name include-internal)
  "Build a unified graph spanning multiple packages. Cross-package calls between
the listed packages are automatically captured."
  (let* ((name (or graph-name (format nil "codegraph/multi")))
         (g (ariadne:make-graph :name name))
         (all-syms '())
         (sym-set (make-hash-table :test 'eq)))
    ;; Collect all symbols from all packages
    (dolist (pd package-designators)
      (let ((pkg (find-package pd)))
        (when pkg
          (if include-internal
              (do-symbols (sym pkg)
                (when (eq (symbol-package sym) pkg)
                  (push sym all-syms)
                  (setf (gethash sym sym-set) t)))
              (do-external-symbols (sym pkg)
                (push sym all-syms)
                (setf (gethash sym sym-set) t))))))
    ;; Index each package's symbols
    (dolist (pd package-designators)
      (let ((pkg (find-package pd)))
        (when pkg
          (let ((pkg-uri (format nil "pkg:~(~A~)" (package-name pkg))))
            (dolist (sym all-syms)
              (when (eq (symbol-package sym) pkg)
                (let ((uri (symbol-uri sym))
                      (kind (classify-symbol sym))
                      (externalp (eq (nth-value 1 (find-symbol (symbol-name sym) pkg)) :external)))
                  (ariadne:add-triple g uri +type+ (string-downcase (symbol-name kind)))
                  (ariadne:add-triple g uri +in-package+ pkg-uri)
                  (when externalp
                    (ariadne:add-triple g pkg-uri +exports+ uri))
                  (when (and include-internal (not externalp))
                    (ariadne:add-triple g uri "cg:internal" "true"))
                  (case kind
                    (:class (index-class g sym uri))
                    (:generic-function (index-generic g sym uri)))
                  (index-metadata g sym uri kind)
                  (index-macro-var-deps g sym uri kind all-syms))))))))
    ;; Call graph across all symbols
    (index-call-graph g all-syms (find-package (first package-designators)) nil)
    g))

(defun build-system-graph (system-designator &key include-internal)
  "Build a graph for an ASDF system. Finds the primary package by system name."
  (asdf:load-system system-designator)
  (let* ((sys-name (string-downcase (string system-designator)))
         (pkg (find-package (string-upcase sys-name))))
    (if pkg
        (build-graph (make-symbol (package-name pkg))
                     :graph-name (format nil "codegraph/system/~A" sys-name)
                     :include-internal include-internal)
        (error "Could not find package for system ~A" system-designator))))
