(require :asdf)
;; Initialize source registry with current directory
(asdf:initialize-source-registry (list (make-pathname :directory '(:absolute))))
;; Now try to load our test system
(asdf:load-system :test-system)
(format t "~&SUCCESS: test-system loaded~%")
(quit)
