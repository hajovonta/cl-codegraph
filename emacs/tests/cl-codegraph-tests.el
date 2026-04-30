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

;;; Buffer package detection

(ert-deftest cl-codegraph-test-detect-buffer-package ()
  "Detect package from in-package form in buffer."
  (with-temp-buffer
    (insert "(in-package #:ariadne)\n\n(defun foo () t)")
    (should (equal (cl-codegraph--detect-buffer-package) "ariadne"))))

(ert-deftest cl-codegraph-test-detect-buffer-package-string ()
  "Detect package from string form."
  (with-temp-buffer
    (insert "(in-package \"MY-PKG\")\n")
    (should (equal (cl-codegraph--detect-buffer-package) "my-pkg"))))

(ert-deftest cl-codegraph-test-detect-buffer-package-keyword ()
  "Detect package from keyword form."
  (with-temp-buffer
    (insert "(in-package :my-pkg)\n")
    (should (equal (cl-codegraph--detect-buffer-package) "my-pkg"))))

(ert-deftest cl-codegraph-test-detect-buffer-package-nil ()
  "Return nil when no in-package form found."
  (with-temp-buffer
    (insert "(defun foo () t)")
    (should (null (cl-codegraph--detect-buffer-package)))))

(ert-deftest cl-codegraph-test-navigation-history ()
  "Navigating to symbols builds a history stack."
  (cl-codegraph--update-view-buffer "first content" "pkg:first")
  (cl-codegraph--update-view-buffer "second content" "pkg:second")
  (let ((buf (get-buffer "*codegraph*")))
    (with-current-buffer buf
      (should (equal cl-codegraph--current-symbol "pkg:second"))
      (should (equal cl-codegraph--history '("pkg:first")))))
  (kill-buffer "*codegraph*"))

(ert-deftest cl-codegraph-test-navigation-no-duplicate-push ()
  "Updating with same symbol doesn't push to history."
  (cl-codegraph--update-view-buffer "content" "pkg:same")
  (cl-codegraph--update-view-buffer "content2" "pkg:same")
  (let ((buf (get-buffer "*codegraph*")))
    (with-current-buffer buf
      (should (null cl-codegraph--history))))
  (kill-buffer "*codegraph*"))

(provide 'cl-codegraph-tests)
;;; cl-codegraph-tests.el ends here
