(defun test () (let ((x 1)) (when (null x) (setf x 2) (setf x 3)) x))
