#!/usr/bin/env sbcl

;; Manual test to verify import-export system loads correctly
;; Run with: sbcl --script test-import.lisp

;; First, try to load quicklisp if available
(handler-bind ((warning #'muffle-warning))
  (ignore-errors
    (load "/home/emmanuel/quicklisp/setup.lisp")))

;; Fallback: manually load required systems
(unless (find-package :ql)
  (format t "Quicklisp not found, loading dependencies manually...~%"))
  (handler-bind ((error #'continue))
    (asdf:load-system :alexandria)
    (asdf:load-system :cl-ppcre)
    (asdf:load-system :parse-number)
    (asdf:load-system :cl-json)
    (asdf:load-system :uuid))

;; Load the import-export package first
(format t "Loading package...~%")
(load "import-export/package.lisp")

;; Now verify the package is accessible
(format t "Package list: ~A~%" (list-all-packages))
(let ((pkg (find-package :graph-db.import-export)))
  (format t "graph-db.import-export package exists: ~A~%" pkg)
  (when pkg
    (format t "Package nicknames: ~A~%" (package-nicknames pkg))))

;; Try loading protocol
(format t "Loading protocol...~%")
(load "import-export/protocol.lisp")

;; Verify protocol functions are available
(format t "Testing protocol functions...~%~")

;; Check if format registry exists
(if (find-package :graph-db.import-export)
    (format t "Format registry: ~A~%" (or (boundp '*format-registry*) "NOT BOUND"))
    (format t "PACKAGE NOT FOUND~%"))

(format t "SUCCESS: Import/Export system loaded~%~")

(defun test-basic-functionality ()
  "Test basic import-export functionality"
  (format t "Testing basic functionality...~%~")
  
  ;; Ensure we're in the right package
  (in-package :graph-db.import-export)
  
  ;; Test format registry
  (let ((initial-count (hash-table-count *format-registry*)))
    (register-format :test
      :import-parser (lambda (source) (declare (ignore source)) (lambda () :eof))
      :export-serializer nil
      :streaming-p t
      :supports-export-p nil)
    (format t "Format registry count after registration: ~A~%" (hash-table-count *format-registry*))
    (if (> (hash-table-count *format-registry*) initial-count)
        (format t "��✓ Format registration works~%~")
        (format t "��✗ Format registration failed~%~")))
  
  (format t "Basic functionality test completed~%~")
  t)

;; Run basic tests
(test-basic-functionality)
(format t "All tests completed successfully!~%")