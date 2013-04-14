;;; skinny.el --- a blog engine with elnode -*- lexical-binding: t -*-

;; Copyright (C) 2012  Nic Ferrier

;; Author: Nic Ferrier <nferrier@ferrier.me.uk>
;; Keywords: hypermedia
;; Version: 0.0.4
;; Package-Requires: ((elnode "0.9.9.6.1")(creole "0.8.17"))

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Skinny is good for hipsters. You can write blog posts in creole and
;; serve them as HTML.

;;; Code:

(elnode-app skinny-dir
  creole esxml)

(defgroup skinny nil
  "A blog engine written with Elnode. Good for hipsters."
  :group 'applications)

(defcustom skinny-port 8090
  "The TCP port to start talking hipster shite on."
  :type '(integer)
  :group 'skinny)

(defcustom skinny-host "localhost"
  "The interface to start talking hipster shite on."
  :type '(string)
  :group 'skinny)

(defcustom skinny-blog-name "skinny"
  "The name of the blog."
  :type '(string)
  :group 'skinny)

(defcustom skinny-blog-css-file-name "blog.css"
  "The name of the CSS file to use for blog posts."
  :type '(file)
  :group 'skinny)

(defgroup skinny-dirs nil
  "Various directories for the Skinny blog.
All paths are relative to `skinny-root'."
  :group 'skinny)

(defcustom skinny-root skinny-dir
  "The root directory of the Skinny site.
By default, this is the directory from which Skinny was loaded.
Blog posts are in a subdirectory, specified by `skinny-blog-dir'."
  :type '(directory)
  :group 'skinny-dirs)

(defcustom skinny-blog-dir "blog/"
  "The directory for blog posts."
  :type '(directory)
  :group 'skinny-dirs)

(defcustom skinny-css-dir "css/"
  "The directory for CSS files."
  :type '(directory)
  :group 'skinny-dirs)

(defcustom skinny-image-dir "images/"
  "The directory for images."
  :type '(directory)
  :group 'skinny-dirs)

(defun skinny-post (httpcon)
  "Return a rendered creole blog post via HTTPCON."
  (let ((skinny-blog-dir (concat skinny-root skinny-blog-dir))
        (css (concat skinny-root skinny-css-dir))
        (creole-image-class "creole")
        (targetfile (elnode-http-mapping httpcon 1)))
    (flet ((elnode-http-mapping (httpcon which)
            (concat targetfile ".creole")))
     (elnode-docroot-for skinny-blog-dir
       with post
       on httpcon
       do
       (elnode-error "Sending blog post: %s" post)
       (elnode-http-start httpcon 200 '("Content-type" . "text/html"))
       (elnode-http-send-string httpcon
         (let ((metadata (skinny/post-meta-data post)))
           (pp-esxml-to-xml
            `(html ()
               ,(esxml-head (cdr (assoc 'title metadata))
                  '(meta ((charset . "UTF-8")))
                  (meta 'author (cdr (assoc 'author metadata)))
                  (css-link skinny-blog-css-file-name)
                  (link 'alternate "application/atom+xml"
                    (concat skinny-root skinny-blog-dir "feed.xml")
                    '((title . "site feed"))))
               (body ()
                 ,(with-temp-buffer
                    (save-match-data
                     (insert-file-contents post))
                    (with-current-buffer
                        (creole-html (current-buffer) nil
                                     :do-font-lock t)
                      (buffer-string))))))))
       (elnode-http-return httpcon)))))

(defun skinny-index-page (httpcon)
  "Return the index page via HTTPCON."
  (let ((page (concat skinny-root "index.html")))
    (elnode-error "Sending index page.")
    (elnode-http-start httpcon 200 '("Content-type" . "text/html"))
    (elnode-http-send-string httpcon
     (with-temp-buffer
       (save-match-data
         (insert-file-contents page)
        (while (search-forward "<!--{{{posts}}}-->" nil t)
          (replace-match (esxml-to-xml (skinny/posts-html-list)) nil t)))
       (buffer-string)))
    (elnode-http-return httpcon)))

(defun skinny/list-posts ()
  "Produce the list of blog posts (file names), sorted by mtime.

Posts are all \"*.creole\" files in `skinny-blog-dir'."
  (sort
   (directory-files (concat skinny-root skinny-blog-dir) t ".*\\.creole\\'" t)
   (lambda (a b)
     (time-less-p
      (elt (file-attributes a) 5)
      (elt (file-attributes b) 5)))))

(defun skinny/posts-html-list ()
  "Produce an HTML list of the posts.
Each post's title is listed, and links to the post itself.
HTML is returned as ESXML, rather than a string."
  (esxml-listify
   (mapcar
    (lambda (post)
      (let ((metadata (skinny/post-meta-data post)))
        (esxml-link
         (save-match-data
           (string-match (expand-file-name
                          (format "%s\\(%s.*\\.creole\\)" skinny-root skinny-blog-dir))
                         post)
           (file-name-sans-extension (match-string 1 post)))
         (cdr (assoc 'title metadata)))))
    (skinny/list-posts))))

(defun skinny/post-meta-data (post)
  "Return corresponding meta-data file for POST file.

Takes the file name of a \".creole\" blog post, and reads the
corresponding \".el\" file, which should contain only a single
alist with the following fields:

title
author -- Just the author name, not name then email.
timestamp -- RFC3339 format
UUID -- Used for the id of feed entries; see RFC4287."
  (with-temp-buffer
    (save-match-data
     (insert-file-contents
      (concat (file-name-sans-extension post) ".el")))
    (read (current-buffer))))

(defun skinny/feed ()
  "Generate an Atom feed from the most recent posts."
  (let* ((posts (skinny/list-posts))
         (last-post-metadata (skinny/post-meta-data
                              (car posts))))
    (concat "<?xml version=\"1.0\"?>"
      (pp-esxml-to-xml
        `(feed ((xmlns . "http://www.w3.org/2005/Atom")
                (xml:lang . "en"))
           ;; Feed metadata.
           (title () ,skinny-blog-name)
           (link ((href . "FIXME: absolute feed URL")
                  (rel . "self")))
           (link ((href . "./")))
           (id () ,(concat "urn:uuid:"
                     (cdr (assoc 'id
                                 last-post-metadata))))
           (updated () ,(cdr (assoc 'timestamp
                                    last-post-metadata)))
           (author ()
             (name () "FIXME: author"))
           ;; Now for the entries.
           ,@(mapcar
              (lambda (post)
                (let ((metadata (skinny/post-meta-data post)))
                  `(entry ()
                     (title () ,(cdr (assoc 'title metadata)))
                     (link ((href . ,(file-name-sans-extension
                                      (file-name-nondirectory post)))))
                     (id () ,(concat "urn:uuid:"
                                     (cdr (assoc 'id metadata))))
                     (updated () ,(cdr (assoc 'timestamp metadata)))
                     (summary ((type . "xhtml"))
                       (div ((xmlns . "http://www.w3.org/1999/xhtml"))
                            "FIXME: post summary")))))
              posts))))))

(defun skinny-feed (httpcon)
  "Return a blog feed via HTTPCON.
Calls `skinny/feed' to generate the feed."
  (elnode-http-start httpcon 200 '("Content-type" . "application/xml"))
  (elnode-http-return httpcon (skinny/feed)))

(defun skinny-router (httpcon)
  "Skinny the blog engine's url router."
  (let ((webserver
         (elnode-webserver-handler-maker
          skinny-root)))
    (elnode-hostpath-dispatcher
     httpcon
     `((,(format "^[^/]+//%sfeed.xml$" skinny-blog-dir) . skinny-feed)
       (,(format "^[^/]+//%s\\(.*\\)" skinny-blog-dir) . skinny-post)
       ("^[^/]+//$" . skinny-index-page)
       ("^[^/]+//\\(.*\\)" . ,webserver)))))

;;;###autoload
(defun skinny-start ()
  (interactive)
  (elnode-start 'skinny-router :port skinny-port :host skinny-host))

(provide 'skinny)

;;; skinny.el ends here
