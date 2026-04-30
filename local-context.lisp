;;;; local-context.lisp — Find local variable binding context from source

(in-package #:cl-codegraph)

(defun local-context (source line column symbol-name)
  "Given SOURCE (string), LINE, COLUMN, and SYMBOL-NAME, find the local binding context.
Returns a plist (:kind :function :value-form) or nil if not a local variable."
  (declare (ignore column))
  (let* ((sym (intern (string-upcase symbol-name) :keyword))
         (pkg (detect-source-package source))
         (forms (read-all-forms source))
         (defun-form (find-enclosing-defun forms line source)))
    (when defun-form
      (let* ((fn-name (string-downcase (princ-to-string (second defun-form))))
             (lambda-list (case (car defun-form)
                            ((defmethod) (third defun-form))
                            (t (third defun-form))))
             (param-names (mapcar (lambda (p)
                                    (if (listp p) (first p) p))
                                  (remove-if (lambda (p)
                                               (and (symbolp p)
                                                    (char= (char (symbol-name p) 0) #\&)))
                                             lambda-list)))
             (body (case (car defun-form)
                     ((defmethod) (cdddr defun-form))
                     (t (cdddr defun-form)))))
        ;; Check lambda list
        (when (member sym param-names
                      :test (lambda (s x)
                              (and (symbolp x)
                                   (string-equal (symbol-name s) (symbol-name x)))))
          (return-from local-context
            (list :kind "parameter" :function fn-name)))
        ;; Check let/let*/dolist/etc bindings in body
        (let ((binding (find-let-binding sym body)))
          (when binding
            (return-from local-context
              (list :kind "let binding"
                    :function fn-name
                    :value-form (let ((*package* (or pkg *package*)))
                                  (write-to-string (second binding) :case :downcase))))))))))

(defun detect-source-package (source)
  "Find the package from the first (in-package ...) form in SOURCE."
  (let ((pos (search "(in-package" source :test #'char-equal)))
    (when pos
      (let* ((form (read-from-string source t nil :start pos))
             (pkg-name (second form)))
        (find-package (if (stringp pkg-name) pkg-name pkg-name))))))

(defun read-all-forms (source)
  "Read all top-level forms from SOURCE string, respecting in-package."
  (with-input-from-string (s source)
    (let ((*package* *package*))
      (loop for form = (read s nil :eof)
            until (eq form :eof)
            do (when (and (listp form) (eq (car form) 'in-package))
                 (let ((pkg (find-package (second form))))
                   (when pkg (setf *package* pkg))))
            collect form))))

(defun find-enclosing-defun (forms line source)
  "Find the defun/defmethod form that contains LINE."
  (let ((best nil))
    (dolist (form forms)
      (when (and (listp form)
                 (member (car form) '(defun defmethod defgeneric defmacro)))
        (let ((form-line (form-start-line form source)))
          (when (and form-line (<= form-line line))
            (setf best form)))))
    best))

(defun form-start-line (form source)
  "Find the line number where FORM starts in SOURCE."
  (let* ((kind (string-downcase (symbol-name (car form))))
         (name (string-downcase (princ-to-string (second form))))
         (pattern (if (eq (car form) 'defmethod)
                      (format nil "(~A ~A " kind name)
                      (format nil "(~A ~A" kind name)))
         (pos 0)
         (last-pos nil))
    (loop
      (let ((found (search pattern source :start2 pos :test #'char-equal)))
        (if found
            (progn (setf last-pos found)
                   (setf pos (1+ found)))
            (return))))
    (when last-pos
      (1+ (count #\Newline source :end last-pos)))))

(defun find-let-binding (sym body)
  "Search BODY for a binding of SYM in let/let*/dolist/dotimes/do forms."
  (dolist (form body)
    (when (listp form)
      (cond
        ((member (car form) '(let let*))
         (dolist (binding (second form))
           (when (listp binding)
             (when (string-equal (symbol-name sym) (symbol-name (first binding)))
               (return-from find-let-binding binding))))
         (let ((result (find-let-binding sym (cddr form))))
           (when result (return-from find-let-binding result))))
        ((member (car form) '(dolist dotimes))
         (let ((var-spec (second form)))
           (when (and (listp var-spec)
                      (string-equal (symbol-name sym) (symbol-name (first var-spec))))
             (return-from find-let-binding var-spec)))
         (let ((result (find-let-binding sym (cddr form))))
           (when result (return-from find-let-binding result))))
        ((eq (car form) 'multiple-value-bind)
         (when (member sym (second form)
                       :test (lambda (s x)
                               (and (symbolp x)
                                    (string-equal (symbol-name s) (symbol-name x)))))
           (return-from find-let-binding (list sym (third form))))
         (let ((result (find-let-binding sym (cdddr form))))
           (when result (return-from find-let-binding result))))
        ((eq (car form) 'destructuring-bind)
         (when (find-in-lambda-list sym (second form))
           (return-from find-let-binding (list sym (third form))))
         (let ((result (find-let-binding sym (cdddr form))))
           (when result (return-from find-let-binding result))))
        (t (let ((result (find-let-binding sym (cdr form))))
             (when result (return-from find-let-binding result))))))))

(defun find-in-lambda-list (sym lambda-list)
  "Check if SYM appears in a possibly nested lambda-list."
  (dolist (item lambda-list)
    (cond
      ((and (symbolp item) (string-equal (symbol-name sym) (symbol-name item)))
       (return-from find-in-lambda-list t))
      ((listp item)
       (when (find-in-lambda-list sym item)
         (return-from find-in-lambda-list t))))))
