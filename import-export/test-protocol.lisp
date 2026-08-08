;;;; graph-db/import-export/test-protocol.lisp
;;;; Simple test to verify format registration and delegation works.

(in-package :graph-db.import-export)

;; Register a dummy format for testing
(register-format :test-dummy
  :import-parser (lambda (source)
                   (declare (ignore source))
                   (lambda () :eof))
  :export-serializer (lambda (target)
                       (declare (ignore target))
                       (lambda (plist) (declare (ignore plist)) nil))
  :streaming-p t
  :supports-export-p t)

;; Test that import-graph delegates to import-format
(defun test-import-delegation ()
  (let ((graph (graph-db:make-graph :test-import "/tmp/test-import/")))
    (unwind-protect
         (multiple-value-bind (stats token)
             (import-graph :format :test-dummy
                           :source :stdin
                           :graph graph
                           :mapping nil
                           :conflict-policy :upsert
                           :chunk-size 10)
           (assert (getf stats :vertices-created))
           (assert (getf stats :edges-created))
           (format t "Import delegation test PASSED~%"))
      (graph-db:close-graph graph)
      (ignore-errors (uiop:delete-directory-tree "/tmp/test-import/" :validate t)))))

;; Test that export-graph delegates to export-format
(defun test-export-delegation ()
  (let ((graph (graph-db:make-graph :test-export "/tmp/test-export/")))
    (unwind-protect
         (let ((stats (export-graph :format :test-dummy
                                    :target :stdout
                                    :graph graph)))
           (assert (getf stats :vertices-exported))
           (format t "Export delegation test PASSED~%"))
      (graph-db:close-graph graph)
      (ignore-errors (uiop:delete-directory-tree "/tmp/test-export/" :validate t)))))

;; Run tests
(defun run-protocol-tests ()
  (format t "Running protocol tests...~%")
  (test-import-delegation)
  (test-export-delegation)
  (format t "All protocol tests PASSED~%"))