;;;; monitor.lisp — Live monitoring with per-symbol dirty tracking

(in-package #:cl-codegraph)

;;; Registry

(defstruct monitor-entry
  graph
  package
  include-internal
  include-external-calls
  dirty-symbols)  ;; hash-table: symbol → t

(defvar *monitors* (make-hash-table :test 'eq)
  "Map from package object to monitor-entry.")

(defvar *hook-installed* nil)

;;; Hook

(defun definition-hook (name new-value)
  "Called by sb-int:*setf-fdefinition-hook* on every function definition."
  (declare (ignore new-value))
  (when (symbolp name)
    (let* ((pkg (symbol-package name))
           (entry (gethash pkg *monitors*)))
      (when entry
        (setf (gethash name (monitor-entry-dirty-symbols entry)) t)))))

(defun install-hook ()
  (unless *hook-installed*
    (push #'definition-hook sb-int:*setf-fdefinition-hook*)
    (setf *hook-installed* t)))

(defun remove-hook ()
  (setf sb-int:*setf-fdefinition-hook*
        (remove #'definition-hook sb-int:*setf-fdefinition-hook*))
  (setf *hook-installed* nil))

;;; Public API

(defun monitor (package-designator &key include-internal include-external-calls)
  "Start monitoring PACKAGE-DESIGNATOR. Builds initial graph and installs hooks.
Returns the graph."
  (let* ((pkg (find-package package-designator))
         (g (build-graph package-designator
                         :include-internal include-internal
                         :include-external-calls include-external-calls))
         (entry (make-monitor-entry
                 :graph g
                 :package pkg
                 :include-internal include-internal
                 :include-external-calls include-external-calls
                 :dirty-symbols (make-hash-table :test 'eq))))
    (setf (gethash pkg *monitors*) entry)
    (install-hook)
    g))

(defun unmonitor (package-designator)
  "Stop monitoring PACKAGE-DESIGNATOR."
  (let ((pkg (find-package package-designator)))
    (remhash pkg *monitors*)
    (when (= 0 (hash-table-count *monitors*))
      (remove-hook))))

(defun graph (package-designator)
  "Get the live graph for PACKAGE-DESIGNATOR. Flushes dirty symbols first.
Returns nil if not monitored."
  (let* ((pkg (find-package package-designator))
         (entry (gethash pkg *monitors*)))
    (when entry
      (flush-dirty entry)
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
