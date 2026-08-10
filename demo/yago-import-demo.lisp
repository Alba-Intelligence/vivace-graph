(in-package #:yago-import-demo)

;; Make sure that the Turtle import is available
;; TODO


;; Location of Yago schema and taxonomy
(defvar +yago-db+ nil)

;; Key namespaces
(defvar *vertex-namespace* (uuidv7:generate))
(defvar *edge-namespace* (uuidv7:generate))

(defparameter *yago-schema-file* (make-pathname :directory '(:relative "yago") 
:name "yago-4.6-schema") :type "zip")

(defparameter *yago-taxonomy-file* (make-pathname :directory '(:relative "yago") 
:name "yago-4.6-taxonomy") :type "zip")

(defparameter *example-resources* 
    '("https://yago-knowledge.org/resource/Elvis_Presley"    
    "https://yago-knowledge.org/resource/Portugal"
    "https://yago-knowledge.org/resource/Bologna_University_Press"
    "https://yago-knowledge.org/resource/Ericsson" 
    "https://yago-knowledge.org/resource/Gilgamesh"))





(defun test-turtle-parser ()
  "Test the Turtle parser with sample data."
  (let* ((parser-fn (import-export.turtle::parse-turtle-file 
                     "import-export/testdata/turtle-sample.ttl"))
         (triples (funcall parser-fn))
         (triple-count (length triples)))
    (format t "Parsed ~A triples from Turtle file~%" triple-count)
    (when (> triple-count 0)
      (format t "First triple: ~A~%" (first triples))
      t)))



(defun run-turtle-tests ()
  "Run Turtle format tests."
  (format t "=== Testing Turtle format support ==~%")
  (test-turtle-parser)
  (format t "=== Turtle format tests completed ==~%"))

;; Run tests when loaded
(run-turtle-tests)

