About
=====

etags-update.el is a Emacs global minor mode that updates your TAGS
when saving a file.


Installing
==========

Put etags-update.pl in your shell's PATH, making sure it is
executable. For instance:

     # mv etags-update.pl ~/bin
     # chmod 755 ~/bin/etags-update.pl

To install the minor-mode, put the etags-update.el file in your
load-path:

     # mv etags-update.el ~/elisp

And require it from your .emacs file:

     (require 'etags-update)


Using
=====

First, load your project's TAGS file:

     M-x visit-tags-table <your-tags-file>

Then toggle the minor-mode on with:

     M-x etags-update-mode

The same command toggles the minor-mode off.

The minor-mode is global, so it will be enabled in all your
buffers. The string "etu" appears in the mode-line when etags-update
is enabled.

When you save a file that is already listed in your TAGS file, the
TAGS file will automatically be updated.

When you save a file that is not listed in your TAGS file,
etags-update can add the file to your TAGS. The etu/append-file-action
variable controls what happens. The default value, 'prompt, asks if
you want to add the file. Etags-update remembers your choice for a
file. 


Customizable Variables
======================

etu/append-file-action
----------------------

What action should be taken when a file not already in TAGS is saved?

If 'nil, do not add the file to TAGS.

If 'add, add the file.

If 'prompt, ask if this file should be added (default).

If set to a function, the function should return one of 'add, 'prompt,
or 'nil.

For example, I use the following code to add files to TAGS when they
are "in my project" according to
[mk-project.el](http://www.littleredbat.net/mk/code/mk-project.html)
and prompt otherwise:

    (defun mk-etags-update-append-file-p (file)
      (cond
        ((and mk-proj-name
              mk-proj-tags-file
              (string= mk-proj-basedir (substring file 0 (length mk-proj-basedir)))) ; eg, file *in* project
         'add)
        (t 'prompt)))

    (setq etu/append-file-prompt 'mk-etags-update-append-file-p)


etu/append-using-font-lock
--------------------------

If non-nil, will only offer to add a buffer to TAGS if the buffer has
font-lock-defaults set. This is a weak indicator that the buffer
represents code, not plain text. Defaults to t.


Caveats
=======

1. etags-update can only update a TAGS file when one has been set
using visit-tags-table. If the tags-file-name variable is nil,
etags-update will not update TAGS. No warning is printed.

2. etags-update only considers one TAGS file. It does not support
multiple files in tags-table-list.

3. When a file is newly added to the TAGS file, it is inserted with
its absolute file name, not a file name relative to the TAGS
file. Therefore, you should completely rebuild your TAGS file if you
move your project to another directory.