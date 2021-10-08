;;; soccer.el --- Fixtures, results, table etc for soccer  -*- lexical-binding: t; -*-

;; Copyright (C) 2021  Md Arif Shaikh

;; Author: Md Arif Shaikh <arifshaikh.astro@gmail.com>
;; Homepage: https://github.com/md-arif-shaikh/soccer
;; Package-Requires: ((emacs "25.1") (dash "2.19.1"))
;; Version: 0.1
;; Keywords: games, soccer, football

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; This package brings soccer (football) fixtures, results, table in your Emacs.
;; Currently it works for
;;
;; 1. Premier League (England)
;; 2. La Liga (Spain)
;; 3. League 1 (France)
;;
;; Other leagues could be easily included and would be in future.
;;
;; To get the time of kick off in your local time, you may want to set the
;; following value accordingly
;;
;; (setq soccer-local-time-utc-offset "+0530") ;; this should be changed to your local one
;;
;; Common Functions:
;;
;; This package comes with handy interactive functions to get useful information in your minibuffer.
;; To invoke a function use "M-x Function" where Function could be any of the following functions
;;
;; Functions	                Actions
;; soccer--fixtures-next	Fixture for the Next match
;; soccer--fixtures-next-5	Fixtures of the Next 5 matches
;; soccer--fixtures-full-in-org	Full fixtures saved in org file
;; soccer--results-last	        Result of the last match
;; soccer--results-last-5	Results of the last 5 matches
;; soccer--results-full-in-org	Full list of results in org file
;; soccer--table                Full Ranking table
;; soccer--table-top-4          Ranking table with top 4 teams
;; soccer--table-bottom-4       Ranking table with bottom 4 teams

;;; Code:

(require 'soccer-leagues)
(require 'soccer-time)
(require 'org)
(require 'dom)
(require 'dash)

(defvar soccer-color--win "#98C379"
  "Color to indicate a win.")
(defvar soccer-color--loss "#BE5046"
  "Color to indicate a loss.")
(defvar soccer-color--draw "#56B6C2"
  "Color to indicate a draw.")
(defvar soccer-color--fixtures "#C678DD"
  "Color to indicate a fixture.")
(defvar soccer-color--time-to-kickoff "#E5C07B"
  "Color to indicate time to kickoff.")

(defface soccer-face--win
  `((t :foreground ,soccer-color--win
       :weight extra-bold
       :box nil
       :underline nil))
  "Face for win."
  :group 'soccer-face)

(defface soccer-face--loss
  `((t :foreground ,soccer-color--loss
       :weight extra-bold
       :box nil
       :underline nil))
  "Face for loss."
  :group 'soccer-face)

(defface soccer-face--draw
  `((t :foreground ,soccer-color--draw
       :weight extra-bold
       :box nil
       :underline nil))
  "Face for draw."
  :group 'soccer-face)

(defface soccer-face--fixtures
  `((t :foreground ,soccer-color--fixtures
       :weight extra-bold
       :box nil
       :underline nil))
  "Face for fixtures."
  :group 'soccer-face)

(defface soccer-face--time-to-kickoff
  `((t :foreground ,soccer-color--time-to-kickoff
       :weight extra-bold
       :box nil
       :underline nil))
  "Face for time to kickoff."
  :group 'soccer-face)

(defvar soccer--league-names)
(setq soccer--league-names (mapcar 'car soccer-leagues--leagues-alist))

(defun soccer--get-league-url (league club)
  "Get the url for a CLUB of LEAGUE."
(cdr (assoc club (cdr (assoc league soccer-leagues--leagues-alist)))))


(defun soccer--get-source-utc-offset (dom)
  "Get the source utc offset from the DOM."
  (let* ((time-offset (-last-item (split-string (car (dom-strings (dom-by-id dom "div_timezone"))) " "))))
    (cond ((equal (length time-offset) 3) (concat time-offset "00")))))

(defun soccer--get-league-data-alist (league club data-type)
  "Get data for DATA-TYPE for a CLUB of a LEAGUE."
  (let* ((url (concat (soccer--get-league-url league club) (format "/%s/" data-type))))
    (with-current-buffer (url-retrieve-synchronously url)
      (let* ((dom (libxml-parse-html-region (point-min) (point-max)))
	     (dates-dom (dom-by-class dom "kick_t_dt"))
	     (times-dom (dom-by-class dom "kick_t_ko"))
	     (homes-dom (dom-by-class dom "home_o"))
	     (aways-dom (dom-by-class dom "away_o"))
	     (source-time-utc-offset (soccer--get-source-utc-offset dom))
	     results-dom
	     (number-of-results (length dates-dom))
	     dates
	     times
	     homes
	     aways
	     results)
	(when (string-equal data-type "results")
	  (setq results-dom (dom-by-class dom "score cshas_ended"))
	  (setq results (cl-loop for n from 0 to number-of-results
			       collect (dom-texts (nth n results-dom)))))
	(setq dates (cl-loop for n from 0 to number-of-results
			     collect (dom-texts (nth n dates-dom))))
	(setq times (cl-loop for n from 0 to number-of-results
			     collect (dom-texts (nth n times-dom))))
	(setq homes (cl-loop for n from 0 to number-of-results
			     collect (dom-texts (nth n homes-dom))))
	(setq aways (cl-loop for n from 0 to number-of-results
			      collect (dom-texts (nth n aways-dom))))
	`(("date" . ,dates)
	  ("time" . ,times)
	  ("source-time-utc-offset" . ,source-time-utc-offset)
	  ("home" . ,homes)
	  ("away" . ,aways)
	  ("result" . ,results))))))

(defun soccer--get-league-data-fixture-stings (dates times homes aways source-time-utc-offset n)
  "Get the fixtures stings to show in buffer for given DATES, TIMES, HOMES, AWAYS, SOURCE-TIME-UTC-OFFSET and N, where is the nth in the results."
  (let* ((date (nth n dates))
	 (time (nth n times))
	 (local-time-list (soccer-time--get-local-time-list time date "\\." 0 1 2 source-time-utc-offset soccer-time-local-time-utc-offset))
	 (local-min (nth 0 local-time-list))
	 (local-hour (nth 1 local-time-list))
	 (local-A/P (nth 2 local-time-list))
	 (match-day-local (nth 3 local-time-list))
	 (match-day-num-local (nth 4 local-time-list))
	 (match-month-local (nth 5 local-time-list))
	 (match-year-local (nth 6 local-time-list))
	 (home (nth n homes))
	 (away (nth n aways))
	 (time-till-kickoff-list (soccer-time--get-time-till-kick-off time date "\\." 0 1 2 source-time-utc-offset soccer-time-local-time-utc-offset))
	 (days-remain (nth 0 time-till-kickoff-list))
	 (hours-remain (nth 1 time-till-kickoff-list))
	 (mins-remain (nth 2 time-till-kickoff-list))
	 time-till-kickoff-string)
    (setq time-till-kickoff-string (format "--> Starts in %s %s %s" (if (> days-remain 0) (format "%s days" days-remain) "") (if (> hours-remain 0) (format "%s hours" hours-remain) "") (if (> mins-remain 0) (format "%s mins" mins-remain) "")))
    (format "%s %s  Local Time: %s %s %s %s %s:%s %s %s - %s %s" date time match-year-local match-month-local (format "%02d" match-day-num-local) match-day-local (format "%02d" local-hour) (format "%02d" local-min) local-A/P (propertize home 'face 'soccer-face--fixtures) (propertize away 'face 'soccer-face--fixtures) (propertize time-till-kickoff-string 'face 'soccer-face--time-to-kickoff))))

(defun soccer--get-league-data-results-stings (dates times homes aways results source-time-utc-offset n)
  "Get the fixtures stings to show in buffer for given DATES, TIMES, HOMES, AWAYS, RESULTS, SOURCE-TIME-UTC-OFFSET and N, where is the nth in the results."
  (let* ((date (nth n dates))
	 (time (nth n times))
	 (local-time-list (soccer-time--get-local-time-list time date "\\." 0 1 2 source-time-utc-offset soccer-time-local-time-utc-offset))
	 (local-min (nth 0 local-time-list))
	 (local-hour (nth 1 local-time-list))
	 (local-A/P (nth 2 local-time-list))
	 (match-day-local (nth 3 local-time-list))
	 (match-day-num-local (nth 4 local-time-list))
	 (match-month-local (nth 5 local-time-list))
	 (match-year-local (nth 6 local-time-list))
	 (home (nth n homes))
	 (away (nth n aways))
	 (result (split-string (nth n results)))
	 (home-goals (car result))
	 (away-goals (nth 0 (last result))))
    (format "%s %s  Local Time: %s %s %s %s %s:%s %s %s" date time match-year-local match-month-local (format "%02d" match-day-num-local) match-day-local (format "%02d" local-hour) (format "%02d" local-min) local-A/P
	    (cond ((> (string-to-number home-goals) (string-to-number away-goals))
		   (format "%s - %s" (propertize (concat home " " home-goals) 'face 'soccer-face--win) (propertize (concat away-goals " " away) 'face 'soccer-face--loss)))
		  ((< (string-to-number home-goals) (string-to-number away-goals))
		   (format "%s - %s" (propertize (concat home " " home-goals) 'face 'soccer-face--loss) (propertize (concat away-goals " " away) 'face 'soccer-face--win)))
		  ((= (string-to-number home-goals) (string-to-number away-goals))
		   (format "%s - %s" (propertize (concat home " " home-goals) 'face 'soccer-face--draw) (propertize (concat away-goals " " away) 'face 'soccer-face--draw)))))))

(defun soccer--get-league-data (league club data-type num-of-results)
  "Get NUM-OF-RESULT number of DATA-TYPE for a CLUB of a LEAGUE."
  (let* ((league-data (soccer--get-league-data-alist league club data-type))
	 (dates (cdr (assoc "date" league-data)))
	 (times (cdr (assoc "time" league-data)))
	 (homes (cdr (assoc "home" league-data)))
	 (aways (cdr (assoc "away" league-data)))
	 (source-time-utc-offset (cdr (assoc "source-time-utc-offset" league-data)))
	 results
	 msg-str
	 (number-of-results (length dates)))
    (message source-time-utc-offset)
    (when (string-equal data-type "results")
      (setq results (cdr (assoc "result" league-data))))
    (if num-of-results
	(setq num-of-results (min number-of-results num-of-results))
      (setq num-of-results number-of-results))
    (setq msg-str (cl-loop for n from 0 to (1- num-of-results)
			   collect (cond ((string-equal data-type "fixtures") (soccer--get-league-data-fixture-stings dates times homes aways source-time-utc-offset n))
					 ((string-equal data-type "results") (soccer--get-league-data-results-stings dates times homes aways results source-time-utc-offset n)))))
    (message "%s" (string-join msg-str "\n"))))

(defun soccer--get-league-data-in-org (league club data-type num-of-results)
  "Get NUM-OF-RESULT number of DATA-TYPE for a CLUB of a LEAGUE."
  (let* ((league-data (soccer--get-league-data-alist league club data-type))
	 (dates (cdr (assoc "date" league-data)))
	 (times (cdr (assoc "time" league-data)))
	 (homes (cdr (assoc "home" league-data)))
	 (aways (cdr (assoc "away" league-data)))
	 results
	 (file-name (format "/tmp/soccer_%s_%s.org" club data-type))
	 (number-of-results (length dates)))
    (when (string-equal data-type "results")
      (setq results (cdr (assoc "result" league-data))))
    (if num-of-results
	(setq num-of-results (min number-of-results num-of-results))
      (setq num-of-results number-of-results))
    (with-temp-buffer
      (insert (format "* %s for %s\n\n" data-type club))
      (insert "|--|--|--|--|--|\n")
      (insert (format "|Date |Time | Home | Away | %s \n" (if (string-equal data-type "results") "score |" "")))
      (insert "|--|--|--|--|\n")
      (dolist (n (number-sequence 0 (1- num-of-results)))
	(let* ((date (nth n dates))
	       (time (nth n times))
	       (home (nth n homes))
	       (away (nth n aways))
	       result)
	  (when (string-equal data-type "results")
	    (setq result (nth n results)))
	  (insert (format "|%s|%s|%s|%s|%s\n" date time home away (if (string-equal data-type "results") (format "%s|" result) "")))
	  (insert "|--|--|--|--|\n")))
      (forward-line (* -1 num-of-results))
      (org-table-align)
      (write-region (point-min) (point-max) file-name)
      (find-file file-name))))

(defun soccer--league-table (league)
  "Get standing table for a LEAGUE."
  (interactive
   (list (completing-read "league: " soccer--league-names)))
  (let* ((url (soccer--get-league-url league "Table")))
    (with-current-buffer (url-retrieve-synchronously url)
      (let* ((dom (libxml-parse-html-region (point-min) (point-max)))
	     (dom-strings-list (-remove #'string-blank-p (dom-strings (nth 0 (dom-by-tag dom 'table)))))
	     (table-header-strings-list (-take 12 dom-strings-list))
	     (results-strings-list (-partition 15 (-drop 12 dom-strings-list)))
	     results-strings)
	(setq results-strings (cl-loop for result in results-strings-list
				      collect (let* ((form-list (-take-last 5 result))
						     (form-string (string-join form-list)))
						(string-join (-flatten (list (-take 10 result) form-string)) " "))))
        (message (string-join (-flatten (list (string-join table-header-strings-list " ") (string-join results-strings "\n"))) "\n"))))))

(defun soccer--get-league-table-data-alist (league)
  "Get data alist for standing table for a LEAGUE."
  (let* ((url (soccer--get-league-url league "Table")))
    (with-current-buffer (url-retrieve-synchronously url)
      (let* ((dom (libxml-parse-html-region (point-min) (point-max)))
	     (dom-strings-list (-remove #'string-blank-p (dom-strings (nth 0 (dom-by-tag dom 'table)))))
	     (results-strings-list (-partition 15 (-drop 12 dom-strings-list)))
	     teams
	     played
	     wins
	     losses
	     goal-for
	     goal-against
	     current-form-list)
	(setq teams (cl-loop for result in results-strings-list
			     collect (nth 2 result)))
	(setq played (cl-loop for result in results-strings-list
			      collect (nth 3 result)))
	(setq wins (cl-loop for result in results-strings-list
			    collect (nth 4 result)))
	(setq losses (cl-loop for result in results-strings-list
			      collect (nth 6 result)))
	(setq goal-for (cl-loop for result in results-strings-list
				collect (car (split-string (nth 7 result)))))
	(setq goal-against (cl-loop for result in results-strings-list
				    collect (nth 2 (split-string (nth 7 result)))))
	(setq current-form-list (cl-loop for result in results-strings-list
				    collect (-take-last 5 result)))
        `(("teams" . ,teams)
	  ("played" . ,played)
	  ("wins" . ,wins)
	  ("losses" . ,losses)
	  ("goal-for" . ,goal-for)
	  ("goal-against" . ,goal-against)
	  ("current-form-list" . ,current-form-list))))))

(defun soccer--table-data (league num top/bottom)
  "Get table for LEAGUE with TOP/BOTTOM NUM teams."
  (let* ((data-alist (soccer--get-league-table-data-alist league))
	 (teams (cdr (assoc "teams" data-alist)))
	 (played (cdr (assoc "played" data-alist)))
	 (wins (cdr (assoc "wins" data-alist)))
	 (losses (cdr (assoc "losses" data-alist)))
	 (goal-for (cdr (assoc "goal-for" data-alist)))
	 (goal-against (cdr (assoc "goal-against" data-alist)))
	 (current-form-list (cdr (assoc "current-form-list" data-alist)))
	 (num-result (min num (length teams)))
	 (start (if (string-equal top/bottom "top") 0 (- (length teams) num-result)))
	 (stop (if (string-equal top/bottom "top") (1- num-result) (1- (length teams))))
	 (header-string (string-join (list "Rank" "Team" "Played" "Won" "Lost" "Drawn" (format "%3s" "GF") (format "%3s" "GA") (format "%3s" "GD") "Points" (format "%5s" "Form")) " "))
	 table-string)
    (setq table-string (cl-loop for n from start to stop
				collect (let ((team (nth n teams))
					      (matches (nth n played))
					      (win (string-to-number (nth n wins)))
					      (loss (string-to-number (nth n losses)))
					      (goalF (string-to-number (nth n goal-for)))
					      (goalA (string-to-number (nth n goal-against)))
					      (current-form (nth n current-form-list))
					      current-form-string-list
					      draw)
					  (setq draw (- (string-to-number matches) win loss))
					  (setq current-form-string-list (cl-loop for form-string in current-form
										  collect (cond ((string-equal form-string "W") (propertize form-string 'face 'soccer-face--win))
												((string-equal form-string "L") (propertize form-string 'face 'soccer-face--loss))
												((string-equal form-string "D") (propertize form-string 'face 'soccer-face--draw)))))
					  (string-join (list (format "%4s" (1+ n)) (format "%4s" team) (format "%6s" matches) (propertize (format "%3s" win) 'face 'soccer-face--win) (propertize (format "%4s" loss) 'face 'soccer-face--loss) (propertize (format "%5s" draw) 'face 'soccer-face--draw) (format "%3s" goalF) (format "%3s" goalA) (format "%3s" (- goalF goalA)) (format "%3s" (+ (* 3 win) draw)) (format "%8s" (string-join current-form-string-list))) " "))))
    (string-join (-insert-at 0 header-string table-string) "\n")))

(defun soccer--table-top-4 (league)
  "Get table for LEAGUE with top 4 teams."
  (interactive
   (list (completing-read "league: " soccer--league-names)))
  (message (soccer--table-data league 4 "top")))

(defun soccer--table-bottom-4 (league)
  "Get table for LEAGUE with bottom 4 teams."
  (interactive
   (list (completing-read "league: " soccer--league-names)))
  (message (soccer--table-data league 4 "bottom")))

(defun soccer--table (league)
  "Get full rank table of a LEAGUE."
  (interactive
   (list (completing-read "league: " soccer--league-names)))
  (let ((buffer-name "*soccer-rank-table*"))
    (generate-new-buffer buffer-name)
    (with-current-buffer buffer-name
      (insert (soccer--table-data league 30 "top")))
    (switch-to-buffer-other-window buffer-name)))

(defun soccer--fixtures-full-in-org (league club)
  "Full fixtures of CLUB of LEAGUE saved in a org file."
  (interactive
   (let* ((league-name (completing-read "league: " soccer--league-names))
	  (club-name (completing-read "club: " (mapcar 'car (cdr (assoc league-name soccer-leagues--leagues-alist))))))
     (list league-name club-name)))
  (soccer--get-league-data-in-org league club "fixtures" nil))

(defun soccer--fixtures-next (league club)
  "The next match of CLUB of LEAGUE."
  (interactive
   (let* ((league-name (completing-read "league: " soccer--league-names))
	  (club-name (completing-read "club: " (mapcar 'car (cdr (assoc league-name soccer-leagues--leagues-alist))))))
     (list league-name club-name)))
  (soccer--get-league-data league club "fixtures" 1))

(defun soccer--fixtures-next-5 (league club)
  "The next 5 matches in fixtures of CLUB of LEAGUE."
  (interactive
   (let* ((league-name (completing-read "league: " soccer--league-names))
	  (club-name (completing-read "club: " (mapcar 'car (cdr (assoc league-name soccer-leagues--leagues-alist))))))
     (list league-name club-name)))
  (soccer--get-league-data league club "fixtures" 5))


(defun soccer--results-full-in-org (league club)
  "Full results of CLUB of LEAGUE saved in a org file."
  (interactive
   (let* ((league-name (completing-read "league: " soccer--league-names))
	  (club-name (completing-read "club: " (mapcar 'car (cdr (assoc league-name soccer-leagues--leagues-alist))))))
     (list league-name club-name)))
  (soccer--get-league-data-in-org league club "results" nil))

(defun soccer--results-last (league club)
  "The last result of CLUB of LEAGUE."
  (interactive
   (let* ((league-name (completing-read "league: " soccer--league-names))
	  (club-name (completing-read "club: " (mapcar 'car (cdr (assoc league-name soccer-leagues--leagues-alist))))))
     (list league-name club-name)))
  (soccer--get-league-data league club "results" 1))

(defun soccer--results-last-5 (league club)
  "The last 5 results of CLUB of LEAGUE."
  (interactive
   (let* ((league-name (completing-read "league: " soccer--league-names))
	  (club-name (completing-read "club: " (mapcar 'car (cdr (assoc league-name soccer-leagues--leagues-alist))))))
     (list league-name club-name)))
  (soccer--get-league-data league club "results" 5))

(provide 'soccer)
;;; soccer.el ends here
