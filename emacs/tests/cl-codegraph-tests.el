;;; cl-codegraph-tests.el --- ERT tests for cl-codegraph.el  -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-codegraph (expand-file-name "../cl-codegraph.el"
                                          (file-name-directory
                                           (or load-file-name buffer-file-name))))

;;; Symbol extraction

(ert-deftest cl-codegraph-test-symbol-at-point-simple ()
  "Extract a simple symbol from buffer text."
  (with-temp-buffer
    (insert "(defun foo (x) (bar x))")
    (goto-char 8) ;; on "foo"
    (should (equal (cl-codegraph--symbol-at-point) "foo"))))

(ert-deftest cl-codegraph-test-symbol-at-point-qualified ()
  "Extract a package-qualified symbol."
  (with-temp-buffer
    (insert "(ariadne:get-triples g)")
    (goto-char 12) ;; on "get-triples" part
    (should (equal (cl-codegraph--symbol-at-point) "ariadne:get-triples"))))

(ert-deftest cl-codegraph-test-symbol-at-point-nil-on-whitespace ()
  "Return nil when point is on whitespace."
  (with-temp-buffer
    (insert "(foo  bar)")
    (goto-char 6) ;; on second space between foo and bar
    (should (null (cl-codegraph--symbol-at-point)))))

;;; Package qualification

(ert-deftest cl-codegraph-test-qualify-symbol-with-package ()
  "Qualify a bare symbol with the buffer package."
  (should (equal (cl-codegraph--qualify-symbol "foo" "my-pkg")
                 "my-pkg:foo")))

(ert-deftest cl-codegraph-test-qualify-symbol-already-qualified ()
  "Don't double-qualify an already qualified symbol."
  (should (equal (cl-codegraph--qualify-symbol "ariadne:query" "my-pkg")
                 "ariadne:query")))

(ert-deftest cl-codegraph-test-qualify-symbol-internal ()
  "Don't re-qualify internal symbols."
  (should (equal (cl-codegraph--qualify-symbol "ariadne::internal-fn" "my-pkg")
                 "ariadne::internal-fn")))

;;; View buffer management

(ert-deftest cl-codegraph-test-update-view-buffer ()
  "update-view-buffer creates/updates the *codegraph* buffer."
  (cl-codegraph--update-view-buffer "test content here")
  (let ((buf (get-buffer "*codegraph*")))
    (should buf)
    (should (equal (with-current-buffer buf
                     (buffer-substring-no-properties (point-min) (point-max)))
                   "test content here")))
  (kill-buffer "*codegraph*"))

(ert-deftest cl-codegraph-test-update-view-buffer-replaces ()
  "Subsequent calls replace buffer content."
  (cl-codegraph--update-view-buffer "first")
  (cl-codegraph--update-view-buffer "second")
  (let ((buf (get-buffer "*codegraph*")))
    (should (equal (with-current-buffer buf
                     (buffer-substring-no-properties (point-min) (point-max)))
                   "second")))
  (kill-buffer "*codegraph*"))

;;; Staleness

(ert-deftest cl-codegraph-test-request-staleness ()
  "A response is stale if the request ID doesn't match current."
  (let ((cl-codegraph--current-request-id 5))
    (should (cl-codegraph--stale-p 3))
    (should (cl-codegraph--stale-p 4))
    (should-not (cl-codegraph--stale-p 5))))

(provide 'cl-codegraph-tests)
;;; cl-codegraph-tests.el ends here
