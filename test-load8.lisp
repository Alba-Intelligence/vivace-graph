(require :asdf)
;; Initialize source registry with current directory as string
(asdf:initialize-source-registry (list "."))
;; Now try to load our test system
(asdf:load-system :test-system)
(format t "~&SUCCESS: test-system loaded~%")
(quit)
