;;; cl-codegraph.el --- Live code graph view for Common Lisp  -*- lexical-binding: t; -*-

;; Copyright (C) 2026
;; Author: Developer
;; Package-Requires: ((emacs "27.1") (glue "0.0.1"))
;; Keywords: lisp, tools

;;; Commentary:

;; Provides a live *codegraph* buffer that shows the graph context
;; (callers, callees, type, slots) of the symbol at point.
;; Updates automatically as you navigate CL source code.
;;
;; Requires cl-codegraph loaded in the Lisp image with a package monitored.

;;; Code:

(require 'glue)

(defgroup cl-codegraph nil
  "Live code graph view for Common Lisp."
  :group 'lisp)

(defcustom cl-codegraph-idle-delay 0.3
  "Seconds of idle time before updating the codegraph view."
  :type 'number
  :group 'cl-codegraph)

(defcustom cl-codegraph-buffer-name "*codegraph*"
  "Name of the codegraph view buffer."
  :type 'string
  :group 'cl-codegraph)

;;; Internal state

(defvar cl-codegraph--current-request-id 0
  "Monotonically increasing request counter for staleness detection.")

(defvar cl-codegraph--last-symbol nil
  "Last symbol we queried, to avoid redundant requests.")

(defvar cl-codegraph--idle-timer nil
  "Idle timer for debounced updates.")

(defvar cl-codegraph--package nil
  "The monitored package name (string).")

;;; Symbol extraction

(defun cl-codegraph--symbol-at-point ()
  "Return the Lisp symbol at point as a string, or nil.
Handles package-qualified symbols (pkg:sym, pkg::sym)."
  (let ((bounds (bounds-of-thing-at-point 'symbol)))
    (when bounds
      (save-excursion
        ;; Extend backwards past : and preceding symbol (package prefix)
        (goto-char (car bounds))
        (when (and (> (car bounds) 1)
                   (eq (char-before) ?:))
          (backward-char)
          (when (and (> (point) 1) (eq (char-before) ?:))
            (backward-char))
          (let ((prefix-bounds (bounds-of-thing-at-point 'symbol)))
            (when prefix-bounds
              (setq bounds (cons (car prefix-bounds) (cdr bounds))))))
        (let ((sym (buffer-substring-no-properties (car bounds) (cdr bounds))))
          (when (not (string-blank-p sym))
            (downcase sym)))))))

(defun cl-codegraph--qualify-symbol (sym package)
  "Qualify SYM with PACKAGE if not already qualified."
  (if (string-match ":" sym)
      sym
    (concat (downcase package) ":" sym)))

;;; View buffer

(defvar-local cl-codegraph--history nil
  "Navigation history stack for the codegraph buffer.")

(defvar-local cl-codegraph--current-symbol nil
  "Currently displayed symbol in the codegraph buffer.")

(defvar cl-codegraph-view-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'cl-codegraph-visit-symbol-at-point)
    (define-key map (kbd "l") #'cl-codegraph-back)
    (define-key map (kbd "q") #'quit-window)
    map)
  "Keymap for cl-codegraph view buffer.")

(define-derived-mode cl-codegraph-view-mode special-mode "Codegraph"
  "Major mode for the *codegraph* view buffer.
\\{cl-codegraph-view-mode-map}")

(defun cl-codegraph--update-view-buffer (content &optional symbol)
  "Update the *codegraph* buffer with CONTENT. Track SYMBOL for navigation."
  (let ((buf (get-buffer-create cl-codegraph-buffer-name)))
    (with-current-buffer buf
      (unless (eq major-mode 'cl-codegraph-view-mode)
        (cl-codegraph-view-mode))
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert content)
        (goto-char (point-min))
        (cl-codegraph--buttonize-symbols))
      (when (and symbol (not (equal symbol cl-codegraph--current-symbol)))
        (when cl-codegraph--current-symbol
          (push cl-codegraph--current-symbol cl-codegraph--history))
        (setq cl-codegraph--current-symbol symbol)))))

(defun cl-codegraph--buttonize-symbols ()
  "Make symbol references in the buffer clickable."
  (save-excursion
    (goto-char (point-min))
    (while (re-search-forward "^  \\(?:calls\\|called-by\\): \\(.+\\)$" nil t)
      (let ((start (match-beginning 1))
            (end (match-end 1))
            (line-content (match-string 1)))
        ;; Split by ", " and buttonize each symbol
        (let ((pos start))
          (dolist (sym (split-string line-content ", "))
            (let ((sym-start pos)
                  (sym-end (+ pos (length sym))))
              (make-text-button sym-start sym-end
                                'action #'cl-codegraph--button-action
                                'cl-codegraph-symbol sym
                                'face 'link
                                'help-echo (format "Visit %s" sym))
              (setq pos (+ sym-end 2)))))))))

(defun cl-codegraph--button-action (button)
  "Navigate to the symbol associated with BUTTON."
  (let ((sym (button-get button 'cl-codegraph-symbol)))
    (cl-codegraph--navigate-to sym)))

(defun cl-codegraph--navigate-to (sym)
  "Query and display SYM in the codegraph buffer."
  (let ((form `(cl-codegraph:describe-symbol
                (cl-codegraph:graph ,(intern (concat ":" cl-codegraph--package)))
                ,sym)))
    (glue-send-async form
                     (lambda (result)
                       (when result
                         (cl-codegraph--update-view-buffer result sym)
                         (cl-codegraph--ensure-view-window))))))

(defun cl-codegraph-visit-symbol-at-point ()
  "Navigate to the symbol at point in the codegraph buffer."
  (interactive)
  (let ((button (button-at (point))))
    (if button
        (button-activate button)
      ;; Try raw symbol at point
      (let ((sym (thing-at-point 'symbol t)))
        (when sym
          (cl-codegraph--navigate-to (downcase sym)))))))

(defun cl-codegraph-back ()
  "Go back to the previous symbol in navigation history."
  (interactive)
  (if cl-codegraph--history
      (let ((prev (pop cl-codegraph--history)))
        (setq cl-codegraph--current-symbol nil) ;; prevent double-push
        (cl-codegraph--navigate-to prev))
    (message "No previous symbol")))

(defun cl-codegraph--ensure-view-window ()
  "Ensure the codegraph buffer is visible in a side window."
  (let ((buf (get-buffer cl-codegraph-buffer-name)))
    (when (and buf (not (get-buffer-window buf)))
      (display-buffer-in-side-window buf '((side . right) (window-width . 50))))))

;;; Staleness

(defun cl-codegraph--stale-p (request-id)
  "Return t if REQUEST-ID is older than the current request."
  (< request-id cl-codegraph--current-request-id))

;;; Query dispatch

(defun cl-codegraph--query-symbol (sym)
  "Send an async query for SYM to the Lisp side."
  (setq cl-codegraph--current-request-id
        (1+ cl-codegraph--current-request-id))
  (let ((req-id cl-codegraph--current-request-id)
        (form `(cl-codegraph:describe-symbol
                (cl-codegraph:graph ,(intern (concat ":" cl-codegraph--package)))
                ,sym)))
    (glue-send-async form
                     (lambda (result)
                       (unless (cl-codegraph--stale-p req-id)
                         (when result
                           (cl-codegraph--update-view-buffer result sym)
                           (cl-codegraph--ensure-view-window)))))))

;;; Idle timer callback

(defun cl-codegraph--on-idle ()
  "Called after idle delay. Query symbol at point if changed."
  (when (and cl-codegraph-mode cl-codegraph--package)
    (let* ((sym-raw (cl-codegraph--symbol-at-point))
           (sym (when sym-raw
                  (cl-codegraph--qualify-symbol sym-raw cl-codegraph--package))))
      (when (and sym (not (equal sym cl-codegraph--last-symbol)))
        (setq cl-codegraph--last-symbol sym)
        (cl-codegraph--query-symbol sym)))))

;;; Minor mode

(defun cl-codegraph--start-timer ()
  "Start the idle timer."
  (unless cl-codegraph--idle-timer
    (setq cl-codegraph--idle-timer
          (run-with-idle-timer cl-codegraph-idle-delay t
                               #'cl-codegraph--on-idle))))

(defun cl-codegraph--stop-timer ()
  "Stop the idle timer."
  (when cl-codegraph--idle-timer
    (cancel-timer cl-codegraph--idle-timer)
    (setq cl-codegraph--idle-timer nil)))

;;;###autoload
(define-minor-mode cl-codegraph-mode
  "Minor mode for live code graph view.
Shows callers, callees, and metadata for the symbol at point
in a dedicated side buffer."
  :lighter " CG"
  :group 'cl-codegraph
  (if cl-codegraph-mode
      (cl-codegraph--start-timer)
    (cl-codegraph--stop-timer)))

;;;###autoload
(defun cl-codegraph-set-package (package)
  "Set the monitored PACKAGE for cl-codegraph queries."
  (interactive "sPackage: ")
  (setq cl-codegraph--package (downcase package)))

;;; Interactive commands

;;;###autoload
(defun cl-codegraph-describe ()
  "Show codegraph info for symbol at point."
  (interactive)
  (let* ((sym-raw (cl-codegraph--symbol-at-point))
         (sym (when sym-raw
                (cl-codegraph--qualify-symbol
                 sym-raw (or cl-codegraph--package "cl-user")))))
    (when sym
      (cl-codegraph--query-symbol sym))))

;;;###autoload
(defun cl-codegraph-show-callers ()
  "Show who calls the symbol at point."
  (interactive)
  (let* ((sym-raw (cl-codegraph--symbol-at-point))
         (sym (when sym-raw
                (cl-codegraph--qualify-symbol
                 sym-raw (or cl-codegraph--package "cl-user"))))
         (form `(format nil "~{~A~%~}"
                        (cl-codegraph:who-calls-p
                         (cl-codegraph:graph ,(intern (concat ":" cl-codegraph--package)))
                         ,sym))))
    (when sym
      (glue-send-async form
                       (lambda (result)
                         (cl-codegraph--update-view-buffer
                          (format "Callers of %s:\n\n%s" sym (or result "none")))
                         (cl-codegraph--ensure-view-window))))))

;;;###autoload
(defun cl-codegraph-show-callees ()
  "Show what the symbol at point calls."
  (interactive)
  (let* ((sym-raw (cl-codegraph--symbol-at-point))
         (sym (when sym-raw
                (cl-codegraph--qualify-symbol
                 sym-raw (or cl-codegraph--package "cl-user"))))
         (form `(format nil "~{~A~%~}"
                        (cl-codegraph:what-calls
                         (cl-codegraph:graph ,(intern (concat ":" cl-codegraph--package)))
                         ,sym))))
    (when sym
      (glue-send-async form
                       (lambda (result)
                         (cl-codegraph--update-view-buffer
                          (format "Callees of %s:\n\n%s" sym (or result "none")))
                         (cl-codegraph--ensure-view-window))))))

(provide 'cl-codegraph)
;;; cl-codegraph.el ends here
