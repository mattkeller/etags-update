;;; etags-update.el --- update TAGS when saving a file
;;
;; Minor mode to update TAGS when a file is saved

;; Copyright (C) 2009  Matt Keller <mattkeller at gmail dot com>
;;
;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 2, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;; Commentary:
;;
;; etags-update is a Emacs global minor mode that updates your TAGS
;; when saving a file.  See the README file for more information:
;; https://github.com/mattkeller/etags-update#readme
;;
;; Note: etags-update.el requires etags-update.pl in your PATH.

;;; Code:

(defvar etu/etags-update-version "0.1"
  "As tagged at http://github.com/mattkeller/etags-update/tree/master")

(defgroup etags-update nil
  "Minor mode to update the TAGS file when a file is saved"
  :group 'tools)

(defcustom etu/append-using-font-lock t
  "If non-nil, will only offer to add a buffer to TAGS if the
buffer has font-lock-defaults set. This is a weak indicator
that the buffer represents code, not plain text."
  :type 'boolean
  :group 'etags-update)

(defcustom etu/append-file-action 'prompt
  "What action should be taken when a file not already in TAGS is saved?
If `nil', do not add the file to TAGS.
If `add', add the file.
If `prompt', ask if this file should be added.
If set to a function, the function should return one of 'add, 'prompt, or 'nil."
  :type '(choice (const add)
                 (const prompt)
                 (const nil)
                 (function))
  :group 'etags-update)

(defvar etu/proc-buf "*etags-update*"
  "Buffer where etags-update.pl will write its stdout")

(defvar etu/no-prompt-files (make-hash-table :test 'equal)
  "A collection of files not to be prompted for in file append situations")

(defun etu/append-prompt-file ()
  "Remove the curent-buffers's file from the no-prompt-files
 collection. Then, when the file is saved and
 `etu/append-file-action' is 'prompt, will prompt to add this
 file, even if you've answered \"no\" to the prompt before."
  (interactive)
  (remhash (buffer-file-name (current-buffer)) etu/no-prompt-files))

(defun etu/tags-file-dir ()
  "Return full directory of the TAGS file (or nil if no tags buffer exists)"
  (when tags-file-name
      (with-current-buffer (get-file-buffer tags-file-name)
        (expand-file-name default-directory))))

(defun etu/file-at-line ()
  "Capture the filename on this line. May return nil."
  (let ((line (buffer-substring (line-beginning-position) (line-end-position))))
      ;; TODO this regex doesn't just match 'file' lines
      (if (string-match "^\\(.*\\),[0-9]+$" line)
          (match-string 1 line)
        nil)))

;; TODO: use this as a heuristic?
(defun etu/absolute-filenames-p ()
  "Does the TAGS file use relative or absolute filenames?"
  (let ((absolute 0)
        (relative 0))
    (when tags-file-name
      (with-current-buffer (get-file-buffer tags-file-name)
        (save-excursion
          (goto-char (point-min))
          (while (re-search-forward "^$" nil t)
            (forward-line 1)
            (let ((file (etu/file-at-line)))
              (when file
                (if (file-name-absolute-p file)
                    (incf absolute)
                  (incf relative))))))))
    (message "TAGS: %s relative, %s absolute" relative absolute)
    (> absolute 0)))

(defun etu/file-str-in-tags-buffer (buffer file-str)
  "Given a file-str which is a relative or absolute filename,
find a matching file in the given TAGS buffer. Return the
matching filename or nil."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-min))
      (let ((match))
          (while (and (search-forward file-str nil t) (not match))
            (let ((file-in-tags (etu/file-at-line)))
              (when (and file-in-tags (string= file-str file-in-tags))
                (setq match file-in-tags))))
          match))))

(defun etu/test-file-str-in-tags-buffer ()
  "Testing utu/file-str-in-tags-buffer"
  (with-temp-buffer
    (insert "junkline\n")
    (insert "/home/mk/foo,10\n")
    (insert "bar,10\n")
    (insert "/home/mk/abcdefg,10\n")
    (assert (string= "/home/mk/foo" (etu/file-str-in-tags-buffer (current-buffer) "/home/mk/foo")))
    (assert (string= "bar" (etu/file-str-in-tags-buffer (current-buffer) "bar")))
    (assert (string= "/home/mk/abcdefg" (etu/file-str-in-tags-buffer (current-buffer) "/home/mk/abcdefg")))
    (assert (null (etu/file-str-in-tags-buffer (current-buffer) "/home/mk/abc")))
    (assert (null (etu/file-str-in-tags-buffer (current-buffer) "bcd")))
    (assert (null (etu/file-str-in-tags-buffer (current-buffer) "mk/abcdefg")))
    (assert (null (etu/file-str-in-tags-buffer (current-buffer) "junkline")))))

(defun etu/file-in-tags (file)
  "Given a absolute filename, search for it, or its filename
relative to the TAGS file directory, in the TAGS buffer. Return
the match or nil."
  (assert (file-name-absolute-p file))
  (let* ((tags-buffer (get-file-buffer tags-file-name))
         (tags-dir    (etu/tags-file-dir))
         (file-rel    (substring file (length tags-dir))))
    (or (etu/file-str-in-tags-buffer tags-buffer file)
        (and (string= file (concat tags-dir file-rel)) ; ensure file-rel is in tags-dir
             (etu/file-str-in-tags-buffer tags-buffer file-rel)))))

(defun etu/update-cb (process event)
  "Callback fn to handle etags-update.pl termination"
  (cond
   ((string= event "finished\n")
    ;; Manualy re-visit TAGS if we appended a new file -- we might not
    ;; have use find-tags between saves and we don't want to re-prompt
    ;; to add the file.
    (visit-tags-table (expand-file-name tags-file-name))
    (message "Refreshing TAGS file ...done")
    (when (get-buffer  etu/proc-buf)
      (kill-buffer (get-buffer etu/proc-buf))))
   (t (message "Refreshing TAGS file failed. Event was %s. See buffer %s." event etu/proc-buf))))

(defun etu/append-file-p (file)
  "Should we add this file to TAGS?"
  (let ((action etu/append-file-action))
    (when (functionp etu/append-file-action)
      (setq action (funcall etu/append-file-action file)))
    (cond
     ((eq action 'nil) nil)
     ((eq action 'add) t)
     ((eq action 'prompt)
      (cond
       ((gethash file etu/no-prompt-files) nil)
       ((and etu/append-using-font-lock (null font-lock-defaults)) nil)
       ((not (y-or-n-p (concat "Add " file " to the TAGS file? ")))
        (puthash file 1 etu/no-prompt-files)
        nil)
       (t nil)))
     (t (error "Invalid etu/append-file-action action: %s" action)))))

(defun etu/update-tags-for-file ()
  "Update the TAGS file for the file of the current buffer. If
the file is not already in TAGS, maybe add it."
  (interactive)
  (catch 'etu/update-tags-for-file
    (when tags-file-name
      (let ((tags-file-full-name (expand-file-name tags-file-name)))
        (unless (get-file-buffer tags-file-full-name)
          (visit-tags-table tags-file-full-name))
        (assert (get-file-buffer tags-file-full-name)))
      (let* ((file              (buffer-file-name (current-buffer)))
             (file-in-tags      (etu/file-in-tags file))
             (cmd               (concat "etags-update.pl " tags-file-name " " file-in-tags))
             (proc-name         "etags-update")
             (default-directory (etu/tags-file-dir)))
        (if (string= file tags-file-name)
            (throw 'etu/update-tags-for-file nil))
        (unless file-in-tags
          (unless (etu/append-file-p file)
            (throw 'etu/update-tags-for-file nil))
          ;; TODO use relative or absolute path? For now, we'll use
          ;; absolute paths. How often do you move your source code OR
          ;; your TAGS file and not completely rebuild TAGS?
          (setq cmd (concat "etags -o " tags-file-name " -a " file)))
        (message "Refreshing TAGS file for %s..." file)
        (start-process-shell-command proc-name etu/proc-buf cmd)
        (set-process-sentinel (get-process proc-name) 'etu/update-cb)))))

(define-minor-mode etags-update-mode
  "Minor mode to update the TAGS file when a file is saved.

Requires etags-update.pl to be in your PATH. Does not use
tags-table-list, only tags-file-name. It is helpful to set
tags-revert-without-query to `t' to avoid tedious prompting."
  nil
  :global t
  :lighter " etu"
  (if etags-update-mode
      (add-hook 'after-save-hook 'etu/update-tags-for-file)
    (remove-hook 'after-save-hook 'etu/update-tags-for-file)))

(provide 'etags-update)

;; etags-update.el ends here
