;;; HNSW Spike - Heap Functions
(in-package :hnsw-spike)

(defun heap-push! (heap item score-key)
  (let ((new-index (aref heap 0)))
    ;; Expand heap if needed
    (when (>= new-index (array-dimension heap 0))
      (let ((new-size (max (* (array-dimension heap 0) 2) 32)))
        (setf (aref heap 0) new-size
              heap (adjust-array heap (list new-size) :initial-element nil :fill-pointer 0))))
    (let ((i (1- (aref heap 0))))
      (setf (aref heap i) item
            (aref heap 0) (1+ (aref heap 0)))
      (loop while (> i 1)
            for parent = (floor (1- i) 2)
            when (<= (funcall score-key (aref heap parent))
                     (funcall score-key (aref heap i)))
            do (return)
            do (rotatef (aref heap i) (aref heap parent))
               (setf i parent)))))

(defun heap-pop! (heap score-key)
  (let ((count (aref heap 0)))
    (when (zerop count)
      (return-from heap-pop! nil))
    (let ((result (aref heap 1)))
      ;; Move last element to root and sift down
      (when (> count 1)
        (let ((last-index (1- count)))
          (setf (aref heap 1) (aref heap last-index))
          (setf (aref heap 0) (1- count))
          ;; Sift down from root
          (let ((i 1))
            (tagbody
             loop-start
               (let* ((left (* i 2))
                      (right (+ left 1))
                      (smallest i))
                 (when (and (< left (aref heap 0))
                            (< (funcall score-key (aref heap left))
                               (funcall score-key (aref heap smallest))))
                   (setf smallest left))
                 (when (and (< right (aref heap 0))
                            (< (funcall score-key (aref heap right))
                               (funcall score-key (aref heap smallest))))
                   (setf smallest right))
                 (when (= smallest i)
                   (go loop-end))
                 (rotatef (aref heap i) (aref heap smallest))
                 (setf i smallest)
                 (go loop-start))
             loop-end)))
      result))))
