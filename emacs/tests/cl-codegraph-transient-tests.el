;;; cl-codegraph-transient-tests.el --- Tests for transient menu commands  -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-codegraph (expand-file-name "../cl-codegraph.el"
                                          (file-name-directory
                                           (or load-file-name buffer-file-name))))

(ert-deftest cl-codegraph-test-transient-prefix-defined ()
  "The transient prefix command exists."
  (should (fboundp 'cl-codegraph-menu)))

(ert-deftest cl-codegraph-test-menu-bound-in-keymap ()
  "The menu is bound to ? in cl-codegraph-view-mode-map."
  (should (eq (lookup-key cl-codegraph-view-mode-map (kbd "?"))
              'cl-codegraph-menu)))

(provide 'cl-codegraph-transient-tests)
;;; cl-codegraph-transient-tests.el ends here
