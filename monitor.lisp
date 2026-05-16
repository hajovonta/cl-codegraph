;;;; monitor.lisp — Live monitoring with per-symbol dirty tracking

(in-package #:cl-codegraph)

;;; Registry

(defstruct monitor-entry
  graph
  package
  include-internal
  include-external-calls
  dirty-symbols   ;; hash-table: symbol → t
  indexing-p)     ;; t while background indexing is in progress

(defvar *monitors* (make-hash-table :test 'eq)
  "Map from package object to monitor-entry.")

(defvar *hook-installed* nil)

(defvar *index-lock* (sb-thread:make-mutex :name "cl-codegraph-index")
  "Mutex to serialize background indexing (Ariadne graphs are not thread-safe).")

;;; Hook

(defun definition-hook (name new-value)
  "Called by sb-int:*setf-fdefinition-hook* on every function definition."
  (declare (ignore new-value))
  (mark-symbol-dirty name))

(defun mark-symbol-dirty (name)
  "Mark NAME as dirty in its package's monitor, if monitored."
  (when (symbolp name)
    (let* ((pkg (symbol-package name))
           (entry (when pkg (gethash pkg *monitors*))))
      (when entry
        (setf (gethash name (monitor-entry-dirty-symbols entry)) t)))))

(defvar *%defvar-sym* (find-symbol "%DEFVAR" :sb-impl))
(defvar *%defparameter-sym* (find-symbol "%DEFPARAMETER" :sb-impl))
(defvar *load-defclass-sym* (find-symbol "LOAD-DEFCLASS" :sb-pcl))

(defun install-hook ()
  (unless *hook-installed*
    (push #'definition-hook sb-int:*setf-fdefinition-hook*)
    (sb-int:encapsulate *%defvar-sym* 'cl-codegraph
                        (lambda (orig &rest args)
                          (mark-symbol-dirty (first args))
                          (apply orig args)))
    (sb-int:encapsulate *%defparameter-sym* 'cl-codegraph
                        (lambda (orig &rest args)
                          (mark-symbol-dirty (first args))
                          (apply orig args)))
    (sb-int:encapsulate *load-defclass-sym* 'cl-codegraph
                        (lambda (orig &rest args)
                          (mark-symbol-dirty (first args))
                          (apply orig args)))
    (setf *hook-installed* t)))

(defun remove-hook ()
  (setf sb-int:*setf-fdefinition-hook*
        (remove #'definition-hook sb-int:*setf-fdefinition-hook*))
  (sb-int:unencapsulate *%defvar-sym* 'cl-codegraph)
  (sb-int:unencapsulate *%defparameter-sym* 'cl-codegraph)
  (sb-int:unencapsulate *load-defclass-sym* 'cl-codegraph)
  (setf *hook-installed* nil))

;;; Public API

(defvar *background-index-threshold* 200
  "Packages with more symbols than this are indexed in the background.")

(defun monitor (package-designator &key include-internal include-external-calls)
  "Start monitoring PACKAGE-DESIGNATOR. Builds initial graph and installs hooks.
For large packages (>*background-index-threshold* symbols), indexing runs in a
background thread. Returns the graph immediately.
If already monitored, returns the existing graph."
  (let* ((pkg (find-package package-designator))
         (existing (gethash pkg *monitors*)))
    (when existing
      (return-from monitor (monitor-entry-graph existing)))
    (let* ((sym-count (let ((n 0))
                      (if include-internal
                          (do-symbols (s pkg) (when (eq (symbol-package s) pkg) (incf n)))
                          (do-external-symbols (s pkg) (incf n)))
                      n))
         (g (ariadne:make-graph :name (format nil "codegraph/~(~A~)" (package-name pkg))))
         (entry (make-monitor-entry
                 :graph g
                 :package pkg
                 :include-internal include-internal
                 :include-external-calls include-external-calls
                 :dirty-symbols (make-hash-table :test 'eq)
                 :indexing-p nil)))
    (setf (gethash pkg *monitors*) entry)
    (install-hook)
    (if (> sym-count *background-index-threshold*)
        ;; Background indexing for large packages
        (progn
          (setf (monitor-entry-indexing-p entry) t)
          (format t "~&; cl-codegraph: indexing ~A (~D symbols) in background...~%"
                  (package-name pkg) sym-count)
          (sb-thread:make-thread
           (lambda ()
             (let ((result (sb-thread:with-mutex (*index-lock*)
                             (build-graph package-designator
                                          :include-internal include-internal
                                          :include-external-calls include-external-calls))))
               (setf (monitor-entry-graph entry) result)
               (setf (monitor-entry-indexing-p entry) nil)
               (when ariadne::*web-server*
                 (ariadne:explorer-add-graph result))
               (format t "~&; cl-codegraph: ~A indexing complete (~D triples).~%"
                       (package-name pkg) (ariadne:triple-count result))))
           :name (format nil "cl-codegraph-index-~A" (package-name pkg)))
          g)
        ;; Synchronous for small packages
        (let ((result (build-graph package-designator
                                   :include-internal include-internal
                                   :include-external-calls include-external-calls)))
          (setf (monitor-entry-graph entry) result)
          (when ariadne::*web-server*
            (ariadne:explorer-add-graph result))
          result)))))

(defun unmonitor (package-designator)
  "Stop monitoring PACKAGE-DESIGNATOR."
  (let ((pkg (find-package package-designator)))
    (remhash pkg *monitors*)
    (when (= 0 (hash-table-count *monitors*))
      (remove-hook))))

(defun ensure-monitor (package-designator)
  "Monitor PACKAGE-DESIGNATOR if not already monitored. Returns the graph."
  (let ((pkg (find-package package-designator)))
    (unless pkg
      (return-from ensure-monitor nil))
    (unless (gethash pkg *monitors*)
      (monitor package-designator :include-internal t)))
  (graph package-designator))

(defun resolve-symbol-from-uri (uri)
  "Resolve a symbol URI like \"pkg:name\" or \"pkg::name\" to the actual symbol."
  (let* ((double (search "::" uri))
         (colon-pos (or double (position #\: uri)))
         (pkg-name (when colon-pos (subseq uri 0 colon-pos)))
         (sym-name (when colon-pos
                     (subseq uri (if double (+ 2 double) (1+ colon-pos)))))
         (pkg (when pkg-name (find-package (string-upcase pkg-name)))))
    (when (and pkg sym-name)
      (find-symbol (string-upcase sym-name) pkg))))

(defun describe-symbol-live (package-designator uri)
  "Auto-monitor PACKAGE-DESIGNATOR if needed, then describe URI.
Tries both exported (:) and internal (::) forms if needed.
Falls back to the symbol's home package if not found in the requested one.
Handles method URIs directly from the graph.
Works during background indexing with partial results."
  (ensure-monitor package-designator)
  ;; Also ensure-monitor the symbol's home package if different
  (let ((sym (resolve-symbol-from-uri uri)))
    (when sym
      (let ((home-pkg (symbol-package sym)))
        (when (and home-pkg (not (eq home-pkg (find-package package-designator))))
          (ensure-monitor (intern (package-name home-pkg) :keyword))))))
  (let* ((pkg (find-package package-designator))
         (entry (when pkg (gethash pkg *monitors*)))
         (g (when entry (monitor-entry-graph entry)))
         (indexing (when entry (monitor-entry-indexing-p entry))))
    ;; Method URIs — look up directly in graph
    (when (search "/method/" uri)
      (return-from describe-symbol-live
        (describe-method-node g uri)))
    ;; Normal symbol lookup
    (let ((result (if (and indexing
                           (not (ariadne:get-triples g :subject uri :predicate +type+)))
                      (describe-symbol-quick uri)
                      (describe-symbol g uri))))
      ;; If not found, try internal form
      (when (and g (not indexing)
                 (not (ariadne:get-triples g :subject uri :predicate +type+))
                 (not (search "::" uri)))
        (let* ((colon-pos (position #\: uri))
               (internal-uri (when colon-pos
                               (concatenate 'string
                                            (subseq uri 0 colon-pos)
                                            "::"
                                            (subseq uri (1+ colon-pos))))))
          (when (and internal-uri
                     (ariadne:get-triples g :subject internal-uri :predicate +type+))
            (setf result (describe-symbol g internal-uri)))))
      ;; If still not found, try the symbol's home package
      (when (and (not indexing)
                 (or (null g)
                     (not (ariadne:get-triples g :subject uri :predicate +type+))))
        (let* ((sym (resolve-symbol-from-uri uri))
               (home-pkg (when sym (symbol-package sym))))
          (when (and home-pkg (not (eq home-pkg pkg)))
            (let* ((home-key (intern (package-name home-pkg) :keyword))
                   (home-entry (gethash home-pkg *monitors*))
                   (home-g (when home-entry (monitor-entry-graph home-entry)))
                   (home-indexing (when home-entry (monitor-entry-indexing-p home-entry))))
              (if home-indexing
                  (setf result (describe-symbol-quick uri))
                  (when home-g
                    (let ((home-uri (symbol-uri sym)))
                      (when (ariadne:get-triples home-g :subject home-uri :predicate +type+)
                        (setf result (describe-symbol home-g home-uri))))))))))
      ;; Check if any relevant package is still indexing
      (let* ((sym (resolve-symbol-from-uri uri))
             (home-pkg (when sym (symbol-package sym)))
             (home-entry (when home-pkg (gethash home-pkg *monitors*)))
             (any-indexing (or indexing
                              (when home-entry (monitor-entry-indexing-p home-entry)))))
        (when any-indexing
          (setf result (concatenate 'string result
                                    (format nil "~%  (indexing in progress...)~%")))))
      result)))

(defun describe-symbol-quick (uri)
  "Quick introspection-based describe without the graph. Used during background indexing."
  (let* ((sym (resolve-symbol-from-uri uri)))
    (if (null sym)
        (format nil "~A~%  (symbol not found)~%" uri)
        (let ((display-uri (symbol-uri sym)))
          (with-output-to-string (s)
            (format s "~A~%" display-uri)
            (format s "  type: ~A~%" (classify-symbol sym))
            (when (and (fboundp sym)
                       (not (macro-function sym)))
              (let ((ll (ignore-errors (sb-introspect:function-lambda-list sym))))
                (when ll (format s "  args: ~A~%" (string-upcase (princ-to-string ll))))))
            (let ((doc (or (documentation sym 'function)
                           (documentation sym 'variable)
                           (when (find-class sym nil) (documentation (find-class sym) t)))))
              (when doc (format s "  doc:  ~A~%" doc))))))))

(defun describe-method-node (graph uri)
  "Describe a method node URI from the graph."
  (with-output-to-string (s)
    (format s "~A~%" uri)
    (let ((specs (mapcar #'ariadne:triple-object
                         (ariadne:get-triples graph :subject uri :predicate +specializes-on+)))
          (calls (mapcar #'ariadne:triple-object
                         (ariadne:get-triples graph :subject uri :predicate +calls+)))
          (gf (mapcar #'ariadne:triple-object
                      (ariadne:get-triples graph :subject uri :predicate +method-of+))))
      (when gf
        (format s "  method-of: ~A~%" (first gf)))
      (when specs
        (format s "  specializes: ~{~A~^, ~}~%" specs))
      (when calls
        (format s "  calls:~%")
        (dolist (c calls) (format s "    ~A~%" c))))))

(defun graph (package-designator)
  "Get the live graph for PACKAGE-DESIGNATOR. Flushes dirty symbols first.
Returns nil if not monitored."
  (let* ((pkg (find-package package-designator))
         (entry (gethash pkg *monitors*)))
    (when entry
      (unless (monitor-entry-indexing-p entry)
        (flush-dirty entry))
      (monitor-entry-graph entry))))

;;; Incremental update

(defun flush-dirty (entry)
  "Re-index all dirty symbols in ENTRY's graph."
  (let ((dirty (monitor-entry-dirty-symbols entry))
        (g (monitor-entry-graph entry))
        (pkg (monitor-entry-package entry))
        (include-internal (monitor-entry-include-internal entry)))
    (when (< 0 (hash-table-count dirty))
      (let ((all-symbols '()))
        ;; Collect the full symbol set for call-graph context
        (if include-internal
            (do-symbols (sym pkg)
              (when (eq (symbol-package sym) pkg)
                (push sym all-symbols)))
            (do-external-symbols (sym pkg)
              (push sym all-symbols)))
        ;; Re-index each dirty symbol
        (maphash (lambda (sym _)
                   (declare (ignore _))
                   (when (and (symbol-package sym)
                              (eq (symbol-package sym) pkg))
                     (reindex-symbol g sym all-symbols)))
                 dirty)
        (clrhash dirty)))))

(defun reindex-symbol (graph sym all-symbols)
  "Remove all triples for SYM and re-index it."
  (let ((uri (symbol-uri sym)))
    ;; Remove triples where sym is subject
    (dolist (tr (ariadne:get-triples graph :subject uri))
      (ariadne:remove-triple graph
                             (ariadne:triple-subject tr)
                             (ariadne:triple-predicate tr)
                             (ariadne:triple-object tr)))
    ;; Remove calledBy triples pointing to this symbol from others
    (dolist (tr (ariadne:get-triples graph :object uri :predicate +calls+))
      (ariadne:remove-triple graph
                             (ariadne:triple-subject tr)
                             (ariadne:triple-predicate tr)
                             (ariadne:triple-object tr)))
    (dolist (tr (ariadne:get-triples graph :object uri :predicate +called-by+))
      (ariadne:remove-triple graph
                             (ariadne:triple-subject tr)
                             (ariadne:triple-predicate tr)
                             (ariadne:triple-object tr)))
    ;; Re-index if symbol still exists and is fbound/bound
    (when (symbol-package sym)
      (let ((kind (classify-symbol sym))
            (pkg (symbol-package sym))
            (externalp (eq (nth-value 1 (find-symbol (symbol-name sym) (symbol-package sym))) :external)))
        (when (or externalp (not (eq kind :other)))
          (let ((pkg-uri (format nil "pkg:~(~A~)" (package-name pkg))))
            (ariadne:add-triple graph uri +type+ (string-downcase (symbol-name kind)))
            (ariadne:add-triple graph uri +in-package+ pkg-uri)
            (when externalp
              (ariadne:add-triple graph pkg-uri +exports+ uri))
            (case kind
              (:class (index-class graph sym uri))
              (:generic-function (index-generic graph sym uri)))
            (index-metadata graph sym uri kind)
            (index-macro-var-deps graph sym uri kind all-symbols)
            ;; Re-index call edges for this symbol
            (when (fboundp sym)
              (let ((sym-set (make-hash-table :test 'eq)))
                (dolist (s all-symbols)
                  (setf (gethash s sym-set) t))
                (dolist (callee-fn (callees-of sym))
                  (let ((callee-name (function-name-of callee-fn)))
                    (when (and (symbolp callee-name)
                               (symbol-package callee-name)
                               (gethash callee-name sym-set)
                               (not (eq callee-name sym)))
                      (let ((callee-uri (symbol-uri callee-name)))
                        (ariadne:add-triple graph uri +calls+ callee-uri)
                        (ariadne:add-triple graph callee-uri +called-by+ uri)))))))))))))
