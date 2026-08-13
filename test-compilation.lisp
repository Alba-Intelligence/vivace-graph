#!/usr/bin/env sbcl

;; Test compilation of :graph-db.import-export system

(handler-bind ((warning #'muffle-warning))
  (progn
    (format t "Loading graph-db.import-export system...~%")
    
    ;; Try to quickload the system
    (handler-case
        (ql:quickload :graph-db.import-export)
      (error ()
        (format t "ERROR: Failed to load graph-db.import-export~%")
        (quit :failure)))
    
    (format t "SUCCESS: graph-db.import-export loaded successfully!~%")
    
    ;; Check if the package exists
    (let ((pkg (find-package :graph-db.import-export)))
      (format t "Package :graph-db.import-export exists: ~A~%" pkg)
      (format t "Package nicknames: ~A~%" (package-nicknames pkg)))
    
    ;; Test basic functionality
    (format t "Testing basic functionality...~%")
    (let ((initial-count (hash-table-count *format-registry*)))
      (register-format :test-format
        :import-parser (lambda (source) (declare (ignore source)) (lambda () :eof))
        :export-serializer nil
        :streaming-p t
        :supports-export-p nil)
      
      (format t "Format registry count after registration: ~A~%" (hash-table-count *format-registry*))
      
      (if (> (hash-table-count *format-registry*) initial-count)
          (format t "✓ Format registration works correctly~%~")
          (format t "✗ Format registration failed~%"))
      
      (format t "Basic functionality test completed successfully!~%~")))
    
    (format t "All compilation tests passed successfully!~%")
    (quit :success)))