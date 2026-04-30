;;;; local-context.lisp — Find local variable binding context from source

(in-package #:cl-codegraph)

(defun local-context (source line column symbol-name)
  "Given SOURCE (string), LINE, COLUMN, and SYMBOL-NAME, find the local binding context.
Returns a plist (:kind :function :value-form) or nil if not a local variable."
  (declare (ignore column))
  (let* ((sym (intern (string-upcase symbol-name) :keyword))
         (forms (read-all-forms source))
         (defun-form (find-enclosing-defun forms line source)))
    (when defun-form
      (let ((fn-name (string-downcase (princ-to-string (second defun-form))))
            (lambda-list (third defun-form))
            (body (cdddr defun-form)))
        ;; Check lambda list
        (when (member sym lambda-list
                      :test (lambda (s x)
                              (and (symbolp x)
                                   (string-equal (symbol-name s) (symbol-name x)))))
          (return-from local-context
            (list :kind "parameter" :function fn-name)))
        ;; Check let/let* bindings in body
        (let ((binding (find-let-binding sym body)))
          (when binding
            (return-from local-context
              (list :kind "let binding"
                    :function fn-name
                    :value-form (string-upcase
                                 (princ-to-string (second binding)))))))))))

(defun read-all-forms (source)
  "Read all top-level forms from SOURCE string."
  (with-input-from-string (s source)
    (loop for form = (read s nil :eof)
          until (eq form :eof)
          collect form)))

(defun find-enclosing-defun (forms line source)
  "Find the defun/defmethod form that contains LINE."
  (let ((line-positions (compute-line-positions source)))
    (dolist (form forms)
      (when (and (listp form)
                 (member (car form) '(defun defmethod defgeneric defmacro)))
        ;; Check if this form spans the target line
        ;; Simple heuristic: find which defun comes before our line
        (let ((form-line (form-start-line form source line-positions)))
          (when (and form-line (<= form-line line))
            (return form)))))))

(defun compute-line-positions (source)
  "Return a vector mapping character positions to line numbers."
  (let ((lines (make-array (length source) :element-type 'fixnum))
        (line 1))
    (dotimes (i (length source))
      (setf (aref lines i) line)
      (when (char= (char source i) #\Newline)
        (incf line)))
    lines))

(defun form-start-line (form source line-positions)
  "Find the line number where FORM starts in SOURCE. Heuristic: search for the form's name."
  (declare (ignore line-positions))
  (let* ((name (and (listp form) (>= (length form) 2)
                    (princ-to-string (second form))))
         (pos (when name (search name source :test #'char-equal))))
    (when pos
      (1+ (count #\Newline source :end pos)))))

(defun find-let-binding (sym body)
  "Search BODY for a let/let* binding of SYM. Returns the binding pair or nil."
  (dolist (form body)
    (when (listp form)
      (cond
        ((member (car form) '(let let*))
         (dolist (binding (second form))
           (when (listp binding)
             (when (string-equal (symbol-name sym) (symbol-name (first binding)))
               (return-from find-let-binding binding))))
         ;; Also recurse into the let body
         (let ((result (find-let-binding sym (cddr form))))
           (when result (return-from find-let-binding result))))
        ;; Recurse into other forms
        (t (let ((result (find-let-binding sym (cdr form))))
             (when result (return-from find-let-binding result))))))))
