(require :asdf)
;; Let's see what systems ASDF knows about
(format t "~&Systems known to ASDF: ~{~A~^, ~}~%" (asdf:list-systems()))
;; Try to find our system
(handler-bind ((error (lambda (c) (format t "~&Error: ~A~%" c) (invoke-restart (find-restart 'continue)))))
  (asdf:load-system :graph-db/core))
(format t "~&SUCCESS: graph-db/core loaded~%")
(quit)
