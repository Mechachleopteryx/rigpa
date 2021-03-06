(require 'ht)
(require 'rigpa-text-parsers)
(require 'rigpa-meta)

(evil-define-state mode
  "Mode state."
  :tag " <M> "
  :message "-- MODE --"
  :enable (normal))

;; recall mode in each buffer, default to nil so it isn't undefined
(defvar-local rigpa-recall nil)

;; registry of known modes
(defvar rigpa-modes
  (ht))

(defun rigpa-register-mode (mode)
  "Register MODE-NAME for use with rigpa."
  (let ((name (chimera-mode-name mode))
        (entry-hook (chimera-mode-entry-hook mode))
        (exit-hook (chimera-mode-exit-hook mode)))
    (ht-set! rigpa-modes name mode)
    (add-hook exit-hook #'rigpa-remember-for-recall)
    (add-hook entry-hook #'rigpa-reconcile-level)))

(defun rigpa-unregister-mode (mode)
  "Unregister MODE-NAME."
  (let ((name (chimera-mode-name mode))
        (entry-hook (chimera-mode-entry-hook mode))
        (exit-hook (chimera-mode-exit-hook mode)))
    (ht-remove! rigpa-modes name)
    (remove-hook exit-hook #'rigpa-remember-for-recall)
    (remove-hook entry-hook #'rigpa-reconcile-level)))

(defun rigpa-enter-mode (mode-name)
  "Enter mode MODE-NAME."
  (chimera-enter-mode (ht-get rigpa-modes mode-name)))

(defun rigpa--enter-level (level-number)
  "Enter level LEVEL-NUMBER"
  (let* ((tower (rigpa--local-tower))
         (tower-height (rigpa-ensemble-size tower))
         (level-number (max (min level-number
                                 (1- tower-height))
                            0)))
    (let ((mode-name (rigpa-editing-entity-name
                      (rigpa-ensemble-member-at-position tower level-number))))
      (rigpa-enter-mode mode-name)
      (setq rigpa--current-level level-number))))

(defun rigpa-enter-lower-level ()
  "Enter lower level."
  (interactive)
  (let ((mode-name (symbol-name evil-state)))
    (if (rigpa-ensemble-member-position-by-name (rigpa--local-tower)
                                                mode-name)
        (when (> rigpa--current-level 0)
          (rigpa--enter-level (1- rigpa--current-level)))
      ;; "not my tower, not my problem"
      ;; if we exited a buffer via a state that isn't in its tower, then
      ;; returning to it "out of band" would find it still that way,
      ;; and Enter/Escape would a priori do nothing since the mode is still
      ;; outside the local tower. Ordinarily, we would return to this
      ;; buffer in a rigpa mode such as buffer mode, which upon
      ;; exiting would look for a recall. Since that isn't the case
      ;; here, nothing would happen at this point, and this is the spot
      ;; where we could have taken some action had we been more civic
      ;; minded. So preemptively go to a safe "default" as a failsafe,
      ;; which would be overridden by a recall if there is one.
      (rigpa--enter-appropriate-mode))))

(defun rigpa--enter-appropriate-mode (&optional buffer)
  "Enter the most appropriate mode in BUFFER.

Priority: (1) provided mode if admissible (i.e. present in tower) [TODO]
          (2) recall if present
          (3) default level for tower (which could default to lowest
              if unspecified - TODO)."
  (with-current-buffer (or buffer (current-buffer))
    (let ((recall-mode (rigpa--local-recall-mode))
          (default-mode (editing-ensemble-default (rigpa--local-tower))))
      (if recall-mode
          ;; recall if available
          (progn (rigpa--clear-local-recall)
                 (rigpa-enter-mode recall-mode))
        ;; otherwise default for tower
        (rigpa-enter-mode default-mode)))))

(defun rigpa-enter-higher-level ()
  "Enter higher level."
  (interactive)
  (let ((mode-name (symbol-name evil-state)))
    (if (rigpa-ensemble-member-position-by-name (rigpa--local-tower)
                                              mode-name)
        (when (< rigpa--current-level
                 (1- (rigpa-ensemble-size (rigpa--local-tower))))
          (rigpa--enter-level (1+ rigpa--current-level)))
      ;; see note for rigpa-enter-lower-level
      (rigpa--enter-appropriate-mode))))

(defun rigpa-enter-lowest-level ()
  "Enter lowest (manual) level."
  (interactive)
  (rigpa--enter-level 0))

(defun rigpa-enter-highest-level ()
  "Enter highest level."
  (interactive)
  (let* ((tower (rigpa--local-tower))
         (tower-height (rigpa-ensemble-size tower)))
    (rigpa--enter-level (- tower-height
                         1))))

(defun rigpa--extract-selected-level ()
  "Extract the selected level from the current representation"
  (interactive)
  (let* ((level-str (thing-at-point 'line t)))
    (let ((num (string-to-number (rigpa--parse-level-number level-str))))
      num)))

(defun rigpa-enter-selected-level ()
  "Enter selected level"
  (interactive)
  (let ((selected-level (rigpa--extract-selected-level)))
    (with-current-buffer (rigpa--get-ground-buffer)
      (rigpa--enter-level selected-level))))

(defun rigpa-reconcile-level ()
  "Adjust level to match current mode.

If the current mode is present in the current tower, ensure that the
current level reflects the mode's position in the tower."
  (interactive)
  (let* ((mode-name (symbol-name evil-state))
         (level-number
          (rigpa-ensemble-member-position-by-name (rigpa--local-tower)
                                                mode-name)))
    (when level-number
      (setq rigpa--current-level level-number))))

(defun rigpa--clear-local-recall (&optional buffer)
  "Clear recall flag if any."
  (with-current-buffer (or buffer (current-buffer))
    (setq-local rigpa-recall nil)))

(defun rigpa--local-recall-mode (&optional buffer)
  "Get the recall mode (if any) in the BUFFER."
  (with-current-buffer (or buffer (current-buffer))
    rigpa-recall))

(defun rigpa--enter-local-recall-mode (&optional buffer)
  "Enter the recall mode (if any) in the BUFFER.

This should generally not be called directly but rather via
hooks. Only call it directly when entering a recall mode
is precisely the thing to be done."
  (with-current-buffer (or buffer (current-buffer))
    (let ((recall rigpa-recall))
      (rigpa--clear-local-recall)
      (when recall
        (rigpa-enter-mode recall)))))

(defun rigpa-remember-for-recall (&optional buffer)
  "Remember the current mode for future recall."
  ;; we're relying on the evil state here even though the
  ;; delegation is hydra -> evil. Probably introduce an
  ;; independent state variable, for which the evil state
  ;; variable can be treated as a proxy for now
  (with-current-buffer (or buffer (current-buffer))
    (let ((mode-name (symbol-name evil-state))
          ;; recall should probably be tower-specific and
          ;; meta-level specific, so that
          ;; we can set it upon entry to a meta mode
          (recall rigpa-recall))
      ;; only set recall here if it is currently in the tower AND
      ;; going to a state outside the tower
      (when (and (rigpa-ensemble-member-position-by-name (rigpa--local-tower)
                                                       mode-name)
                 (not (rigpa-ensemble-member-position-by-name
                       (rigpa--local-tower)
                       (symbol-name evil-next-state))))
        (rigpa-set-mode-recall mode-name)))))

(defun rigpa-set-mode-recall (mode-name)
  "Remember the current state to 'recall' it later."
  (setq-local rigpa-recall mode-name))

(defun rigpa-serialize-mode (mode)
  "A string representation of a mode."
  (let ((name (rigpa-editing-entity-name mode)))
    (concat "|―――"
            (number-to-string level-number)
            "―――|"
            " " (if (equal name (editing-ensemble-default tower))
                    (concat "[" name "]")
                  name))))

(defun rigpa--mode-mode-change (orig-fn &rest args)
  "Change mode."
  (interactive)
  (beginning-of-line)
  (evil-forward-WORD-begin)
  (evil-change-line (point) (line-end-position)))

(defun rigpa--update-tower (name value)
  "Update tower NAME to VALUE."
  (set (intern (concat "rigpa-" name "-tower")) value)
  ;; update complex too
  ;; TODO: this seems hacky, should be a "formalized" way of updating
  ;; editing structures so that all containing ones are aware,
  ;; maybe as part of "state modeling"
  (with-current-buffer (rigpa--get-ground-buffer)
    (setf (nth (seq-position (seq-map #'rigpa-editing-entity-name
                                      (editing-ensemble-members rigpa--complex))
                             name)
               (editing-ensemble-members rigpa--complex))
          value)))

(defun rigpa--reload-tower ()
  "Reparse and reload tower."
  (interactive)
  (condition-case err
      (let* ((fresh-tower (rigpa-parse-tower-from-buffer))
             (name (rigpa-editing-entity-name fresh-tower))
             (original-line-number (line-number-at-pos)))
        (rigpa--update-tower name fresh-tower)
        (setf (buffer-string) "")
        (insert (rigpa-serialize-tower fresh-tower))
        (rigpa--tower-view-narrow fresh-tower)
        (evil-goto-line original-line-number))
    (error (message "parse error %s. Reverting tower..." err)
           (rigpa--tower-view-narrow (rigpa--ground-tower))
           (rigpa--tower-view-reflect-ground (rigpa--ground-tower)))))

(defun rigpa--add-meta-side-effects ()
  "Add side effects for primitive mode operations while in meta mode."
  ;; this should lookup the appropriate side-effect based on the coordinates
  (advice-add #'rigpa-line-move-down :after #'rigpa--reload-tower)
  (advice-add #'rigpa-line-move-up :after #'rigpa--reload-tower)
  (advice-add #'rigpa-line-change :around #'rigpa--mode-mode-change))

(defun rigpa--remove-meta-side-effects ()
  "Remove side effects for primitive mode operations that were added for meta modes."
  (advice-remove #'rigpa-line-move-down #'rigpa--reload-tower)
  (advice-remove #'rigpa-line-move-up #'rigpa--reload-tower)
  (advice-remove #'rigpa-line-change #'rigpa--mode-mode-change))

;; TODO: should have a single function that enters
;; any meta-level, incl. mode, tower, etc.
;; this is the function that does the "vertical" escape
;; some may enter new buffers while other may enter new perspectives
;; for now we can just do a simple dispatch here
(defun rigpa-enter-mode-mode ()
  "Enter a buffer containing a textual representation of the
current editing tower."
  (interactive)
  (rigpa-render-tower-for-mode-mode (rigpa--local-tower))
  (rigpa--switch-to-tower rigpa--current-tower-index) ; TODO: base this on "state" instead
  (rigpa--set-ui-for-meta-modes)
  (rigpa--add-meta-side-effects))

(defun rigpa-exit-mode-mode ()
  "Exit mode mode."
  (interactive)
  (let ((ref-buf (rigpa--get-ground-buffer)))
    (rigpa--revert-ui)
    (rigpa--remove-meta-side-effects)
    (when (eq (with-current-buffer ref-buf
                (rigpa--get-ground-buffer))
              ref-buf)
      (kill-matching-buffers (concat "^" rigpa-buffer-prefix) nil t))
    (switch-to-buffer ref-buf)))

;; = "factory defaults", other mode, and search

;; mode mode as the lowest level upon s-Esc, with tower mode above that achieved via s-Esc again, and so on...
;; i.e. once in any meta mode, you should be able to use the usual L00 machinery incl. e.g. line mode
;; maybe tower mode should only operate on towers - and mode mode could take advantage of a similar (but more minimal) representation as tower mode currently has

(provide 'rigpa-mode-mode)
;;; rigpa-mode-mode.el ends here
