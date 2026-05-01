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
(make-variable-buffer-local 'cl-codegraph--last-symbol)

(defvar cl-codegraph--idle-timer nil
  "Idle timer for debounced updates.")

(defvar cl-codegraph--package nil
  "The monitored package name (string). Buffer-local when set.")
(make-variable-buffer-local 'cl-codegraph--package)

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
    ;; Match any pkg:sym or pkg::sym pattern on indented lines
    (while (re-search-forward "\\b\\([a-z][a-z0-9*+._-]*::?[a-z0-9*+._/-]+\\)" nil t)
      (let ((sym (match-string 1))
            (start (match-beginning 1))
            (end (match-end 1)))
        ;; Only buttonize on indented lines (not the first line which is the title)
        (when (save-excursion
                (goto-char (line-beginning-position))
                (looking-at "  "))
          (make-text-button start end
                            'action #'cl-codegraph--button-action
                            'cl-codegraph-symbol sym
                            'face 'link
                            'help-echo (format "Visit %s" sym)))))))

(defun cl-codegraph--button-action (button)
  "Navigate to the symbol associated with BUTTON: jump to source and update codegraph."
  (let ((sym (button-get button 'cl-codegraph-symbol)))
    (cl-codegraph--navigate-to sym)
    (cl-codegraph--jump-to-definition sym)))

(defun cl-codegraph--jump-to-definition (sym)
  "Jump to SYM's definition in the source window.
Always jumps to the first definition found, no xref popup.
For method URIs, tries to match the specific defmethod."
  (let* ((is-method (string-match "/method/" sym))
         (jump-sym (if is-method
                       (substring sym 0 (match-beginning 0))
                     sym))
         (method-specs (when is-method
                         (downcase (substring sym (match-end 0)))))
         (name (upcase (cl-codegraph--ensure-double-colon jump-sym)))
         (source-window (cl-codegraph--find-source-window)))
    (when source-window
      (with-selected-window source-window
        (let ((xrefs (slime-find-definitions name)))
          (when xrefs
            (slime-push-definition-stack)
            (let ((target (if method-specs
                              (or (cl-codegraph--find-method-xref xrefs method-specs)
                                  (car xrefs))
                            (car xrefs))))
              (slime-pop-to-location (slime-xref.location target) nil)))
          (cl-codegraph--position-on-symbol jump-sym))))))

(defun cl-codegraph--find-method-xref (xrefs method-specs)
  "Find the xref in XREFS whose label matches METHOD-SPECS (e.g. \"graph/t\")."
  (let ((first-spec (car (split-string method-specs "/"))))
    (cl-loop for xref in xrefs
             when (and (string-match "defmethod" (downcase (slime-xref.dspec xref)))
                       (string-match (concat "\\b" (regexp-quote first-spec) "\\b")
                                     (downcase (slime-xref.dspec xref))))
             return xref)))

(defun cl-codegraph--ensure-double-colon (sym)
  "Ensure SYM uses :: (works for both exported and internal in Slime)."
  (cond ((string-match "\\(.+?\\)::\\(.+\\)" sym) sym)  ;; already ::
        ((string-match "\\(.+?\\):\\(.+\\)" sym)
         (concat (match-string 1 sym) "::" (match-string 2 sym)))
        (t sym)))

(defun cl-codegraph--find-source-window ()
  "Find a window displaying a Lisp source file (not *codegraph*)."
  (let ((cg-buf (get-buffer cl-codegraph-buffer-name)))
    (cl-loop for win in (window-list)
             unless (eq (window-buffer win) cg-buf)
             when (with-current-buffer (window-buffer win)
                    (derived-mode-p 'lisp-mode 'common-lisp-mode))
             return win)))

(defun cl-codegraph--position-on-symbol (sym)
  "After jumping to a definition, position point on the symbol name."
  (let ((bare-name (if (string-match ".*::?\\(.+\\)" sym)
                       (match-string 1 sym)
                     sym)))
    (when (re-search-forward (regexp-quote bare-name) (line-end-position 3) t)
      (goto-char (match-beginning 0)))))

(defun cl-codegraph--navigate-to (sym)
  "Query and display SYM in the codegraph buffer. Bypasses staleness check."
  (setq cl-codegraph--last-symbol sym)
  (let* ((pkg (if (string-match "\\(.+?\\)::?" sym)
                  (match-string 1 sym)
                (or cl-codegraph--package "cl-user")))
         (form `(cl-codegraph:describe-symbol-live
                 ,(intern (concat ":" pkg))
                 ,sym)))
    (glue-send-async form
                     (lambda (result)
                       (when result
                         (cl-codegraph--update-view-buffer result sym))))))

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
  "Go back to the previous symbol in navigation history. Jumps source too."
  (interactive)
  (if cl-codegraph--history
      (let ((prev (pop cl-codegraph--history)))
        (setq cl-codegraph--current-symbol nil)
        (let* ((pkg (if (string-match "\\(.+?\\)::?" prev)
                        (match-string 1 prev)
                      (or cl-codegraph--package "cl-user")))
               (form `(cl-codegraph:describe-symbol-live
                       ,(intern (concat ":" pkg))
                       ,prev)))
          (glue-send-async form
                           (lambda (result)
                             (when result
                               (cl-codegraph--update-view-buffer result prev)))))
        (cl-codegraph--jump-to-definition prev))
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
  (let* ((req-id cl-codegraph--current-request-id)
         (pkg (or cl-codegraph--package "cl-user"))
         (file (buffer-file-name))
         (line (line-number-at-pos))
         (col (current-column))
         (bare-name (if (string-match ".*::?\\(.+\\)" sym)
                        (match-string 1 sym)
                      sym))
         (form `(let ((result (cl-codegraph:describe-symbol-live
                               ,(intern (concat ":" pkg))
                               ,sym)))
                  (if (and result (> (length result) (+ (length ,sym) 2))
                           (search "type:" result)
                           (not (search "type: other" result)))
                      result
                      (let ((source ,(when file
                                       `(with-open-file (s ,file)
                                          (let ((buf (make-string (file-length s))))
                                            (read-sequence buf s)
                                            buf)))))
                        (if source
                            (let ((ctx (cl-codegraph:local-context source ,line ,col ,bare-name)))
                              (if ctx
                                  (format nil "~A~%  ~A in: ~A~@[~%  value-form: ~A~]~%"
                                          ,sym
                                          (getf ctx :kind)
                                          (getf ctx :function)
                                          (getf ctx :value-form))
                                  (format nil "~A~%  (not in graph)~%" ,sym)))
                            (format nil "~A~%  (not in graph)~%" ,sym)))))))
    (glue-send-async form
                     (lambda (result)
                       (unless (cl-codegraph--stale-p req-id)
                         (when result
                           (cl-codegraph--update-view-buffer result sym)
                           (cl-codegraph--ensure-view-window)))))))

;;; Buffer package detection

(defun cl-codegraph--detect-buffer-package ()
  "Detect the CL package from the buffer's (in-package ...) form.
Returns lowercase package name string, or nil."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward
           "(in-package\\s-+\\(?:#:\\|:\\|\"\\)\\([^)\"]+\\)" nil t)
      (downcase (match-string 1)))))

;;; Idle timer callback

(defun cl-codegraph--on-idle ()
  "Called after idle delay. Query symbol at point if changed."
  (when cl-codegraph-mode
    (let ((pkg (cl-codegraph--detect-buffer-package)))
      (when pkg
        (setq cl-codegraph--package pkg)
        (let* ((sym-raw (cl-codegraph--symbol-at-point))
               (sym (when sym-raw
                      (cl-codegraph--qualify-symbol sym-raw pkg))))
          (when (and sym (not (equal sym cl-codegraph--last-symbol)))
            (setq cl-codegraph--last-symbol sym)
            (cl-codegraph--query-symbol sym)))))))

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
(defun cl-codegraph-enable-globally ()
  "Enable cl-codegraph-mode in all Lisp buffers (current and future)."
  (interactive)
  (add-hook 'lisp-mode-hook #'cl-codegraph-mode)
  (dolist (buf (buffer-list))
    (with-current-buffer buf
      (when (derived-mode-p 'lisp-mode 'common-lisp-mode)
        (cl-codegraph-mode 1)))))

;;;###autoload
(defun cl-codegraph-set-package (pkg)
  "Set the monitored PACKAGE for cl-codegraph queries."
  (interactive "sPackage: ")
  (setq cl-codegraph--package (downcase pkg)))

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

;;; Transient menu

(require 'transient)

(defun cl-codegraph--run-aggregate-query (form label)
  "Run an aggregate FORM on the Lisp side and display result with LABEL."
  (let ((pkg (or cl-codegraph--package
                 (cl-codegraph--detect-buffer-package)
                 "cl-user")))
    (glue-send-async
     `(let ((g (cl-codegraph:graph ,(intern (concat ":" pkg)))))
        (if g ,form "(package not monitored)"))
     (lambda (result)
       (cl-codegraph--update-view-buffer
        (format "%s\n\n%s" label (or result "nil")))
       (cl-codegraph--ensure-view-window)))))

(transient-define-prefix cl-codegraph-menu ()
  "Codegraph aggregate queries."
  ["Queries"
   ("d" "Dead exports" cl-codegraph-cmd-dead-exports)
   ("u" "Undocumented exports" cl-codegraph-cmd-undocumented)
   ("p" "Unused packages" cl-codegraph-cmd-unused-packages)
   ("y" "Find cycles" cl-codegraph-cmd-cycles)
   ("c" "Call chain..." cl-codegraph-cmd-call-chain)
   ("i" "Impact of..." cl-codegraph-cmd-impact)
   ("D" "Diff (refresh)" cl-codegraph-cmd-diff)
   ("s" "Summary" cl-codegraph-cmd-summary)])

(defun cl-codegraph-cmd-dead-exports ()
  "Show dead exports."
  (interactive)
  (cl-codegraph--run-aggregate-query
   '(format nil "~{~A~%~}" (cl-codegraph:dead-exports g))
   "Dead exports (never called):"))

(defun cl-codegraph-cmd-undocumented ()
  "Show undocumented exports."
  (interactive)
  (cl-codegraph--run-aggregate-query
   '(format nil "~{~A~%~}" (cl-codegraph:undocumented-exports g))
   "Undocumented exports:"))

(defun cl-codegraph-cmd-unused-packages ()
  "Show unused packages."
  (interactive)
  (let ((pkg (or cl-codegraph--package
                 (cl-codegraph--detect-buffer-package)
                 "cl-user")))
    (glue-send-async
     `(let ((g (cl-codegraph:ensure-monitor ,(intern (concat ":" pkg)))))
        (if g
            (format nil "~{~A~%~}" (cl-codegraph:unused-packages g ,(intern (concat ":" pkg))))
            "(package not monitored)"))
     (lambda (result)
       (cl-codegraph--update-view-buffer
        (format "Unused packages in use-list:\n\n%s" (or result "nil")))
       (cl-codegraph--ensure-view-window)))))

(defun cl-codegraph-cmd-cycles ()
  "Show call cycles."
  (interactive)
  (cl-codegraph--run-aggregate-query
   '(let ((cycles (cl-codegraph:find-cycles g)))
      (if cycles
          (format nil "~{~{~A~^ → ~}~%~}" cycles)
          "No cycles found."))
   "Circular call dependencies:"))

(defun cl-codegraph-cmd-call-chain ()
  "Prompt for from and to, show call chain."
  (interactive)
  (let* ((pkg (or cl-codegraph--package "cl-user"))
         (default-from (or cl-codegraph--current-symbol ""))
         (from (read-string (format "Call chain from [%s]: " default-from) nil nil default-from))
         (to (read-string (format "Call chain to: ")))
         (qualified-from (cl-codegraph--qualify-symbol from pkg))
         (qualified-to (cl-codegraph--qualify-symbol to pkg)))
    (glue-send-async
     `(let ((g (cl-codegraph:graph ,(intern (concat ":" pkg)))))
        (if g
            (let ((chain (cl-codegraph:call-chain g ,qualified-from ,qualified-to)))
              (if chain
                  (format nil "~{~A~%  ↓~%~}~A" (butlast chain) (car (last chain)))
                  (format nil "No path found from ~A to ~A" ,qualified-from ,qualified-to)))
            "(package not monitored)"))
     (lambda (result)
       (cl-codegraph--update-view-buffer
        (format "Call chain:\n\n%s" (or result "nil")))
       (cl-codegraph--ensure-view-window)))))

(defun cl-codegraph-cmd-impact ()
  "Show impact of symbol at point."
  (interactive)
  (let ((sym (or cl-codegraph--current-symbol "")))
    (cl-codegraph--run-aggregate-query
     `(let ((impact (cl-codegraph:impact-of g ,sym)))
        (if impact
            (format nil "~A symbols affected:~%~{  ~A~%~}" (length impact) impact)
            "No dependents found."))
     (format "Impact of %s:" sym))))

(defun cl-codegraph-cmd-diff ()
  "Refresh graph and show what changed."
  (interactive)
  (let ((pkg (or cl-codegraph--package "cl-user")))
    (glue-send-async
     `(let ((g (cl-codegraph:graph ,(intern (concat ":" pkg)))))
        (if g
            (let ((diff (cl-codegraph:refresh-graph g ,(intern (concat ":" pkg))
                                                    :include-internal t)))
              (format nil "Added: ~A~%Removed: ~A" (getf diff :added) (getf diff :removed)))
            "(package not monitored)"))
     (lambda (result)
       (cl-codegraph--update-view-buffer
        (format "Diff (changes since last build):\n\n%s" (or result "nil")))
       (cl-codegraph--ensure-view-window)))))

(defun cl-codegraph-cmd-summary ()
  "Show graph summary."
  (interactive)
  (cl-codegraph--run-aggregate-query
   '(cl-codegraph:summary g)
   "Graph summary:"))

;; Bind menu to ? in codegraph view
(define-key cl-codegraph-view-mode-map (kbd "?") #'cl-codegraph-menu)

(provide 'cl-codegraph)
;;; cl-codegraph.el ends here
