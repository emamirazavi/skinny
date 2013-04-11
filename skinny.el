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
        (body-header (concat skinny-root "/template/headerhtml"))
        (body-footer (concat skinny-root "/template/footerhtml"))
        (css (concat skinny-root skinny-css-dir))
        (creole-image-class "creole"))
    (elnode-docroot-for skinny-blog-dir
        with post
        on httpcon
        do
        (elnode-error "Sending blog post: %s" post)
        (elnode-http-start httpcon 200 '("Content-type" . "text/html"))
        (with-stdout-to-elnode httpcon
            (creole-wiki post
             :destination t
             :docroot skinny-blog-dir
             :css (list css)
             :body-header body-header
             :body-footer body-footer)))))

(defun skinny-index-page (httpcon)
  "Return the index page via HTTPCON."
  (let ((page (concat skinny-root "index.html")))
    (elnode-error "Sending index page.")
    (elnode-http-start httpcon 200 '("Content-type" . "text/html"))
    (elnode-http-send-string httpcon
     (with-temp-buffer
       (insert-file-contents page)
       (while (search-forward "<!--{{{posts}}}-->" nil t)
         (replace-match (esxml-to-xml (skinny/posts-html-list)) nil t))
       (buffer-string)))
    (elnode-http-return httpcon)))

(defun skinny-redirector (httpcon)
  "Redirect non creole pages to creole."
  (let ((targetfile (elnode-http-mapping httpcon 1)))
    (flet ((elnode-http-mapping (httpcon which)
             (concat targetfile ".creole")))
      (skinny-post httpcon))))

(defun skinny/list-posts ()
  "Produce the list of blog posts, sorted by mtime.

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
    (lambda (post-file-name)
      (esxml-link
       (save-match-data
         (string-match (expand-file-name
                        (format "%s\\(%s.*\\.creole\\)" skinny-root skinny-blog-dir))
                       post-file-name)
         (match-string 1 post-file-name))
       "FIXME: post-title"))
    (skinny/list-posts))))

(defun skinny-feed (httpcon)
  "For now a dummy feed."
  (elnode-http-start httpcon 200 '("Content-type" . "application/xml"))
  (elnode-http-return httpcon "<?xml version='1.0'?>"))

(defun skinny-router (httpcon)
  "Skinny the blog engine's url router."
  (let ((webserver
         (elnode-webserver-handler-maker
          skinny-root)))
    (elnode-hostpath-dispatcher
     httpcon
     `((,(format "^[^/]+//%sfeed.xml$" skinny-blog-dir) . skinny-feed)
       (,(format "^[^/]+//%s\\(.*\\.creole\\)" skinny-blog-dir) . skinny-post)
       (,(format "^[^/]+//%s\\(.*\\)" skinny-blog-dir) . skinny-redirector)
       ("^[^/]+//$" . skinny-index-page)
       ("^[^/]+//\\(.*\\)" . ,webserver)))))

;;;###autoload
(defun skinny-start ()
  (interactive)
  (elnode-start 'skinny-router :port skinny-port :host skinny-host))

(provide 'skinny)

;;; skinny.el ends here
