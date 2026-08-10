;;;; graph-db/import-export/turtle.lisp
;;;; Turtle (TTL) format parser for YAGO dumps with zip support

(in-package :graph-db.import-export)

;;; ---------------------------------------------------------------------------
;;; Turtle parser with streaming and zip support
;;; ---------------------------------------------------------------------------

(defun turtle-file-extension-p (file-path)
  "Check if file has Turtle-related extension (.ttl, .turtle)"
  (let ((ext (pathname-type file-path)))
    (and ext (member (string-downcase ext) '("ttl" "turtle" "nt")))))

(defun open-turtle-stream (source)
  "Open Turtle source with appropriate parsing based on file type."
  (cond
    ((pathnamep source)
     (let ((ext (pathname-type source)))
       (cond
         ((string= ext "gz")
          (sb-ext:run-program "gzip" (list "-dc" source) :output :stream))
         ((string= ext "zip")
          (handler-case
              (sb-ext:run-program "unzip" (list "-p" source "yago-schema.ttl") :output :stream)
            (error ()
              (sb-ext:run-program "unzip" (list "-p" source "*.ttl") :output :stream))))
         (t
          (open source :direction :input)))))
    ((stringp source)
     (if (string-ends-with source ".gz")
         (sb-ext:run-program "gzip" (list "-dc" source) :output :stream)
         (open source :direction :input)))))

(defun parse-turtle-line (line)
  "Parse a single Turtle line into a triple."
  (let ((line (string-trim '(#\\Space #\\Tab) line)))
    (cond
      ((string= line "") nil)
      ((string-starts-with line "@prefix") nil)
      ((string-starts-with line "@base") nil)
      ((string-starts-with line "@import") nil)
      ((string-starts-with line "@") nil)
      ((string-starts-with line "#") nil)
      (t
       (let* ((parts (split-whitespace line))
              (subject (first parts))
              (predicate (second parts))
              (object (third parts)))
         (when (and subject predicate object)
           (list subject predicate object)))))))

(defun parse-turtle-stream (stream)
  "Parse Turtle stream and return iterator for (subject predicate object) triples."
  (lambda ()
    (loop
      (let ((line (read-line stream nil nil)))
        (when (null line) (return :eof))
        (let ((triple (parse-turtle-line line)))
          (when triple (return triple)))))))

(defun parse-turtle-file (file-path)
  "Parse Turtle file and return list of triples."
  (with-open-file (stream file-path :direction :input)
    (let ((triples '()))
      (loop
        (let ((triple (funcall (parse-turtle-stream stream)))))
          (when (eq triple :eof) (return))
          (when triple (push triple triples))))
      (nreverse triples))))

(defun register-turtle-format ()
  "Register the Turtle format with the format registry."
  (register-format :turtle
    :import-parser 'parse-turtle-stream
    :export-serializer nil
    :streaming-p t
    :supports-export-p nil)
  t)

;; Initialize Turtle format when loaded
(register-turtle-format))