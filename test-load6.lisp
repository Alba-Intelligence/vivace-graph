(require :asdf)
;; Push current directory onto the central registry
(pushnew (make-pathname :directory '(:absolute)) asdf:*central-registry* :test #'equalp)
;; Now try to load our test system
(asdf:load-system :test-system)
(format t "~&SUCCESS: test-system loaded~%")
(quit)
