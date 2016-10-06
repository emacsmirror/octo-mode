
;;; octo-mode.el --- Major mode for Octo assembly language

;; Copyright (C) 2016 John Olsson

;; Author: John Olsson <john@cryon.se>
;; Maintainer: John Olsson <john@cryon.se>
;; URL: https://github.com/cryon/octo-mode
;; Created: 4th October 2016
;; Version: 0.1.0
;; Keywords: language octo

;; This file is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published
;; by the Free Software Foundation, either version 3 of the License,
;; or (at your option) any later version.

;; This file is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this file.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Major mode for editing Octo source code. A high level assembly
;; language for the Chip8 virtual machine.
;; See: https://github.com/JohnEarnest/Octo

;;; Code:

;; TODO:

;; Test indentation code more - its very messy
;; Add support for SuperChip
;; Add custom face for SuperChip instructions deriving
;;  builtin-face or something...
;; Add support for XO-Chip and
;; Custom face for XO-Chip instructions
;; Add :breakpoint <name> statement

;; User definable variables

(defgroup octo nil
  "Support for Octo assembly language."
  :group 'languages
  :prefix "octo-")

(defcustom octo-mode-hook nil
  "Hook run by `octo-mode'."
  :type 'hook
  :group 'octo)

(defcustom octo-indent-offset 2
  "Amount of offset per level of indentation."
  :type 'integer
  :group 'octo)

(defcustom octo-indentation-hint-search-lines 50
  "Maximum number of lines to search for indentation hint."
  :type 'integer
  :group 'octo)

;; Constants

(defconst octo-mode-version "0.1.0"
  "Version of `octo-mode.'")

(defconst octo-label-regexp
  ":\\s-+\\(\\sw+\\)"
  "Regexp matching Octo labels")

(defconst octo-constant-name-regexp
  ":const\\s-+\\(\\sw+\\)"
  "Regexp maching name of Octo constant")

(defconst octo-directives-regexp
  (regexp-opt '(":" ":const" ":alias" ":unpack" ":next" ":org") 'words)
  "Regexp maching Octo directives")

(defconst octo-statements-regexp
  (regexp-opt '("clear" "bcd" "save" "load" "sprite" "jump"
                "jump0" "return" "delay" "buzzer" ";") 'words)
  "Regexp matching Octo statements")

(defconst octo-assignments-regexp
  (regexp-opt '(":=" "+=" "-=" "|=" "&=" "^=" ">>=" "<<=") 'symbols)
  "Regexp maching Octo assignments")

(defconst octo-conditionals-regexp
  (concat
   (regexp-opt '("==" "!=") 'symbols)
   "\\|"
   (regexp-opt '("key" "-key") 'words))
  "Regexp matching Octo conditionals")

(defconst octo-psuedo-ops-regexp
  (regexp-opt '("<" ">" "<=" ">=") 'symbols)
  "Regexp matching Octo psuedo ops")

(defconst octo-control-statements-regexp
  (regexp-opt '("if" "then" "else" "begin" "end" "loop" "again" "while") 'words)
  "Regexp matching Octo control statements")

(defconst octo-registers-regexp
  (regexp-opt '("v0" "v1" "v2" "v3"
                "v4" "v5" "v6" "v7"
                "v8" "v9" "va" "vb"
                "vc" "vd" "ve" "vf"
                "i") 'words)
  "Regexp matching Octo registers")

(defconst octo-special-aliases-regexp
  ":alias\\s-+\\(compare-temp\\)"
  "Regexp matching Octo special aliases")

;; Mode setup

(defvar octo-mode-syntax-table nil
  "Syntax table used on `octo-mode' buffers")

(unless octo-mode-syntax-table
  (setq octo-mode-syntax-table (make-syntax-table))

  ;; # Comments rest of line
  (modify-syntax-entry ?#  "<" octo-mode-syntax-table)
  (modify-syntax-entry ?\n ">" octo-mode-syntax-table)

  ;; : - _ ; Is part of a word
  (modify-syntax-entry ?:  "w" octo-mode-syntax-table)
  (modify-syntax-entry ?-  "w" octo-mode-syntax-table)
  (modify-syntax-entry ?_  "w" octo-mode-syntax-table)
  (modify-syntax-entry ?\; "w" octo-mode-syntax-table)

  ;; Tabs and spaces are whitespaces
  (modify-syntax-entry ?\t  "-" octo-mode-syntax-table)
  (modify-syntax-entry ?\   "-" octo-mode-syntax-table))

;; Font-lock support

(defvar octo-highlights
  `((,octo-label-regexp              . (1 font-lock-function-name-face))
    (,octo-constant-name-regexp      . (1 font-lock-constant-face))
    (,octo-directives-regexp         . (1 font-lock-preprocessor-face))
    (,octo-statements-regexp         . font-lock-keyword-face)
    (,octo-assignments-regexp        . font-lock-constant-face)
    (,octo-conditionals-regexp       . font-lock-builtin-face)
    (,octo-psuedo-ops-regexp         . font-lock-keyword-face)
    (,octo-control-statements-regexp . font-lock-keyword-face)
    (,octo-registers-regexp          . font-lock-variable-face)
    (,octo-special-aliases-regexp    . (1 font-lock-preprocessor-face)))
  "Expressions to highlight in `octo-mode'")

;; Indentation

(defun octo-previous-line-indentation ()
  "Indentation of previos line"
  (save-excursion
    (forward-line -1)
    (current-indentation)))

(defconst octo-block-start-regexp
  "\\s-*\\(\\(:\\s-+\\sw*\\>\\)\\|loop\\|else\\|\\(.*begin\\s-*$\\)\\)"
  "Regexp matching block start")

(defconst octo-block-end-regexp
  "\\s-*\\(again\\|end\\)"
  "Regexp matching block end")

(defun octo-backwards-indentation-hint (max-iter)
  "Returns indentation hint based on previous `max-iter' lines"
  (save-excursion
    (let ((iter octo-indentation-hint-search-lines)
          (hint 0))
      (while (> iter 0)
        (forward-line -1)
        (if (looking-at octo-block-start-regexp)
            (progn
              (setq hint (+ (current-indentation) octo-indent-offset))
              (setq iter 0)))
        (if (looking-at octo-block-end-regexp)
            (progn
              (setq hint (current-indentation))
              (setq iter 0)))
        (setq iter (- iter 1)))
      hint)))

(defun octo-indent-line ()
  "Indent current line as Octo code"
  (interactive)
  (beginning-of-line)
  (indent-line-to
   (max
    0
    (if (or (bobp)(looking-at (concat "\\s-*" octo-label-regexp)))
        0
      (if (or (looking-at octo-block-end-regexp)
              ;; special special else
              (looking-at "\\s-*else"))
          (- (octo-previous-line-indentation) octo-indent-offset)
        (octo-backwards-indentation-hint
         octo-indentation-hint-search-lines))))))

;;;###autoload
(define-derived-mode octo-mode fundamental-mode "Octo"
  "Major mode for editing Octo assembly language.

\\{octo-mode-map}"
  :syntax-table octo-mode-syntax-table
  (set (make-local-variable 'comment-start) "# ")
  (set (make-local-variable 'indent-line-function) 'octo-indent-line)
  (set (make-local-variable 'indent-tabs-mode) nil)

  (setq font-lock-defaults '(octo-highlights)))

;;;###autoload
(add-to-list
 'auto-mode-alist
 '("\\.8o\\'" . octo-mode))

(provide 'octo-mode)

;; Local Variables:
;; coding: utf-8
;; End:

;;; octo-mode.el ends here
