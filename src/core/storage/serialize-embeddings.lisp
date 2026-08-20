(in-package :graph-db)

;; Embedding serialization layer for HNSW vector search
;; Supports multiple precisions: float32, float16, bfloat16, int8
;; Uses SBCL intrinsics where available, with CCL/ECL fallbacks

;; --- Type tag constants for embedding precisions ---
;; (Defined in globals.lisp as +embedding-float32+ etc.)

;; --- Helpers ---

(defun embedding-bytes-per-element (precision)
  "Return bytes-per-element for the given embedding precision."
  (ecase precision
    (float32 4)
    (float16 2)
    (bfloat16 2)
    (int8 1)))

(defun embedding-size-in-bytes (dim precision)
  "Calculate total bytes for a DIM-dimensional embedding with PRECISION."
  (declare (type (unsigned-byte 32) dim))
  (* dim (embedding-bytes-per-element precision)))

(defun validate-embedding-config (dim precision &key (M 16) (ef-construction 200))
  "Validate embedding config parameters. Signals error on invalid values."
  (unless (and (> dim 0) (<= dim 100000))
    (error 'embedding-dimension-mismatch
           :details (format nil "Embedding dim ~A is invalid (must be 1-100000)" dim)))
  (unless (member precision '(float32 float16 bfloat16 int8))
    (error 'embedding-precision-unsupported
           :details (format nil "Precision ~A is not supported" precision)))
  (unless (and (>= M 2) (<= M 100))
    (error 'embedding-dimension-mismatch
           :details (format nil "M ~A is invalid (must be 2-100)" M)))
  (unless (and (>= ef-construction 1) (<= ef-construction 10000))
    (error 'embedding-dimension-mismatch
           :details (format nil "ef-construction ~A is invalid (1-10000)" ef-construction))))

;; --- Float16/Bfloat16 conversion (no SBCL intrinsics for these) ---

(defun encode-float16 (x)
  "Encode a single-float as IEEE 754 half-precision (16-bit), returned as 2 unsigned bytes."
  (let* ((bits (sb-kernel:single-float-bits x))
         (sign (ldb (byte 1 31) bits))
         (exp (ldb (byte 8 23) bits))
         (mant (ldb (byte 23 0) bits))
         (new-exp 0)
         (new-mant 0))
    (cond
      ;; Zero (incl. signed zero)
      ((and (= exp 0) (= mant 0)) 0)
      ;; Subnormal or underflow -> flush to zero
      ((<= exp 112) 0) ; exp <= -15 in float32 maps to flush
      ;; Overflow -> inf
      ((>= exp 143) ; exp >= 16 (after bias adjustment)
       (setf new-exp 31)
       (setf new-mant 0))
      ;; Normalized: adjust exponent bias difference (127 vs 15)
      (t
       (setf new-exp (- exp 112)) ; 127 - 15
       (setf new-mant (ldb (byte 10 13) mant))))
    (let ((result (+ (ash sign 15)
                     (ash (logand new-exp #x1F) 10)
                     (logand new-mant #x3FF))))
      (make-array 2 :element-type '(unsigned-byte 8)
                  :initial-contents (list (ldb (byte 8 0) result)
                                          (ldb (byte 8 8) result))))))

(defun decode-float16 (byte-array &optional (offset 0))
  "Decode IEEE 754 half-precision from BYTE-ARRAY at OFFSET. Returns single-float."
  (let ((raw (+ (aref byte-array offset)
                (ash (aref byte-array (1+ offset)) 8))))
    (let ((sign (ldb (byte 1 15) raw))
          (exp (ldb (byte 5 10) raw))
          (mant (ldb (byte 10 0) raw)))
      (cond
        ;; Zero
        ((and (= exp 0) (= mant 0))
         (if (= sign 1) -0.0 0.0))
        ;; Subnormal
        ((= exp 0)
         (let ((val (* (if (= sign 1) -1 1)
                       (expt 2 -24)
                       mant
                       (expt 2.0d0 -2)))))
           (coerce val 'single-float)))
        ;; Infinity/NaN
        ((= exp 31)
         (if (= mant 0)
             (if (= sign 1) '-infinity.0 'infinity.0)
             'nan.0))
        ;; Normal
        (t
         (let ((val (* (if (= sign 1) -1 1)
                       (expt 2 (- exp 15))
                       (+ 1.0d0 (/ mant 1024.0d0)))))
           (coerce val 'single-float))))))

(defun encode-bfloat16 (x)
  "Encode a single-float as bfloat16 (16-bit), returned as 2 unsigned bytes."
  (let ((bits (sb-kernel:single-float-bits x)))
    ;; bfloat16 is float32 with low 16 bits truncated
    (let ((bf16 (ash bits -16)))
      (make-array 2 :element-type '(unsigned-byte 8)
                  :initial-contents (list (ldb (byte 8 0) bf16)
                                          (ldb (byte 8 8) bf16))))))

(defun decode-bfloat16 (byte-array &optional (offset 0))
  "Decode bfloat16 from BYTE-ARRAY at OFFSET. Returns single-float."
  (let ((raw (+ (aref byte-array offset)
                (ash (aref byte-array (1+ offset)) 8))))
    ;; Restore as float32 by shifting left 16 bits
    (let ((bits (ash raw 16)))
      (sb-kernel:make-single-float bits))))

;; --- Main serialization functions ---

(defun serialize-embedding (vector precision)
  "Serialize a numeric vector to bytes with precision tag.
VECTOR: a simple-array of single-float
PRECISION: float32, float16, bfloat16, or int8
Returns: byte array [type-tag-byte] [data-bytes]"
  (declare (type keyword precision))
  (let* ((dim (length vector))
         (bytes-per-elem (embedding-bytes-per-element precision))
         (data-size (* dim bytes-per-elem))
         (total-size (1+ data-size))
         (result (make-array total-size :element-type '(unsigned-byte 8)))
    (setf (aref result 0)
          (ecase precision
            (float32 +embedding-float32+)
            (float16 +embedding-float16+)
            (bfloat16 +embedding-bfloat16+)
            (int8 +embedding-int8+)))
    (loop for i from 0 below dim
          for src-idx = 0
          do
          (let ((val (aref vector i)))
            (ecase precision
              (float32
                #+sbcl
                (let ((bits (sb-kernel:single-float-bits val)))
                  (loop for byte from 0 below 4
                        do (setf (aref result (+ 1 (* i 4) byte))
                                     (ldb (byte 8 (* byte 8)) bits))))
                #+ccl
                (let ((buf (ccl::single-float-to-bytes val)))
                  (loop for byte from 0 below 4
                        do (setf (aref result (+ 1 (* i 4) byte))
                                (aref buf byte))))
                #-sbcl #.-ccl
                (error "Float32 serialization not supported on this platform"))
              (float16
               (let ((encoded (encode-float16 val)))
                 (setf (aref result (+ 1 (* i 2) 0)) (aref encoded 0))
                 (setf (aref result (+ 1 (* i 2) 1)) (aref encoded 1))))
              (bfloat16
               (let ((encoded (encode-bfloat16 val)))
                 (setf (aref result (+ 1 (* i 2) 0)) (aref encoded 0))
                 (setf (aref result (+ 1 (* i 2) 1)) (aref encoded 1))))
                (int8
                  (setf (aref result (+ 1 i))
                        (ldb (byte 8 0) (floor val)))))))
    result)))

(defun deserialize-embedding (bytes)
  "Deserialize embedding bytes back to a vector.
BYTES: byte array starting with type-tag-byte
Returns: (values vector dim precision)"
  (let* ((type-tag (aref bytes 0))
         (precision (ecase type-tag
                      (+embedding-float32+ 'float32)
                      (+embedding-float16+ 'float16)
                      (+embedding-bfloat16+ 'bfloat16)
                      (+embedding-int8+ 'int8)))
         (dim (ecase precision
                (float32 (floor (1- (length bytes)) 4))
                (float16 (floor (1- (length bytes)) 2))
                (bfloat16 (floor (1- (length bytes)) 2))
                (int8 (1- (length bytes)))))
         (result (make-array dim :element-type (ecase precision
                                                 (float32 'single-float)
                                                 (float16 'single-float)
                                                 (bfloat16 'single-float)
                                                 (int8 '(signed-byte 8))))))
    (loop for i from 0 below dim
          do (ecase precision
               (float32
                #+sbcl
                (let ((bits 0))
                  (loop for byte from 0 below 4
                        do (setf bits (dpb (aref bytes (+ 1 (* i 4) byte))
                                           (byte 8 (* byte 8)) bits)))
                  (setf (aref result i) (sb-kernel:make-single-float bits)))
                #-sbcl (error "Float32 deserialization not supported on this platform"))
               (float16
                (setf (aref result i)
                      (decode-float16 bytes (+ 1 (* i 2)))))
               (bfloat16
                (setf (aref result i)
                      (decode-bfloat16 bytes (+ 1 (* i 2)))))
               (int8
                (setf (aref result i)
                      (if (>= (aref bytes (+ 1 i)) 128)
                          (- (aref bytes (+ 1 i)) 256)
                          (aref bytes (+ 1 i))))))
    (values result dim precision))))

;; --- Canonical node serialization ---

(defun canonicalize-node (node &key (precision :float32) (compressed-p nil))
  "Return a canonical (deterministic) byte representation of NODE's embedding.
Slots are sorted by name; embedding is serialized via serialize-embedding.
Returns: byte-vector"
  (let* ((slot-names (sort (remove-if-not #'symbolp (list-all-slot-names node))
                           #'string<))
         (embedding (slot-value node 'embedding))
         (emb-bytes (when embedding
                      (serialize-embedding embedding precision))))
    (concatenate 'vector
                 (make-array (length slot-names) :element-type '(unsigned-byte 8)
                             :initial-element 0)) ; placeholder for slot name hashes
                 (or emb-bytes #(0)))))

(defun list-all-slot-names (node)
  "Return a list of all slot names defined on NODE's class."
  (mapcar 'slot-definition-name
          (remove-if-not #'(lambda (s)
                             (or (persistent-p s) (ephemeral-p s)))
                           (class-slots (class-of node)))))

(defvar *embedding-serialize-stats* nil
  "When non-nil, accumulate (count total-us) for serialize calls.")

(defun %record-serialize-time (start-time end-time)
  (when *embedding-serialize-stats*
    (push (cons end-time (- end-time start-time)) *embedding-serialize-stats*)))

(defmacro embedding-time (&body body)
  "Measure execution time of BODY, returns (values result elapsed-microseconds)."
  #+sbcl
  (let ((start (gensym "START"))
        (result (gensym "RESULT"))
        (end (gensym "END")))
    `(let ((,start (sb-ext:get-time-of-day)))
       (let ((,result (progn ,@body)))
         (let ((,end (sb-ext:get-time-of-day)))
           (values ,result (- ,end ,start)))))
  #-sbcl ;; Fallback for non-SBCL
  (let ((start (gensym "START"))
        (result (gensym "RESULT"))
        (end (gensym "END")))
    `(let ((,start (get-internal-real-time)))
       (let ((,result (progn ,@body)))
         (let ((,end (get-internal-real-time)))
           (values ,result (- ,end ,start))))))))

;; --- Vector math helpers (for distance calculations) ---

(declaim (inline vector-dot-product-single))
(defun vector-dot-product-single (a b)
  "Compute dot product of two single-float vectors."
  (declare (type (simple-array single-float (*)) a b))
  #+sbcl
  (let ((result 0.0))
    (declare (type single-float result))
    ;; SBCL can optimize this loop well
    (loop for i from 0 below (length a)
          do (incf result (* (aref a i) (aref b i))))
    result)
  #-sbcl
  (let ((result 0.0))
    (loop for i from 0 below (length a)
          do (incf result (* (aref a i) (aref b i))))
    result))

(declaim (inline vector-magnitude-single))
(defun vector-magnitude-single (a)
  "Compute Euclidean norm of a single-float vector."
  (declare (type (simple-array single-float (*)) a))
  (sqrt (vector-dot-product-single a a)))

;; --- Validation functions ---

(defun validate-embedding (vector dim precision)
  "Validate an embedding vector against expected config."
  (unless (= (length vector) dim)
    (error 'embedding-dimension-mismatch
           :expected dim
           :actual (length vector)
           :details "Embedding dimension does not match schema config"))
  (unless (member precision '(float32 float16 bfloat16 int8))
    (error 'embedding-precision-unsupported
           :details (format nil "Precision ~A not supported" precision)))
  ;; Check value ranges for quantized types
  (when (eq precision 'int8)
    (loop for v across vector
          when (or (< v -128) (> v 127))
          do (error 'embedding-value-out-of-range
                    :value v
                    :min -128
                    :max 127)))
  t)

;; --- Memory estimation ---

(defun embedding-memory (dim precision)
  "Estimate memory usage for a single embedding."
  (embedding-size-in-bytes dim precision))

(defun embedding-index-memory-estimate (n-nodes dim precision)
  "Estimate total memory for N-NODES embeddings plus HNSW index overhead."
  (let* ((emb-bytes (embedding-memory dim precision))
         (total-emb (* n-nodes emb-bytes))
         ;; HNSW index: ~2x the embedding size for neighbor lists + graph overhead
         (hnsw-overhead (* total-emb 2))
         ;; Node overhead (ID, pointers, etc.): ~16 bytes per node per layer avg
         (node-overhead (* n-nodes 64)))
    (+ total-emb hnsw-overhead node-overhead)))

;; --- Canonical node serialization ---

(defun canonicalize-node (node &key (precision :float32) (compressed-p nil))
  "Return a canonical (deterministic) byte representation of NODE's embedding.
Slots are sorted by name; embedding is serialized via serialize-embedding.
Returns: byte-vector"
  (let* ((slot-names (sort (remove-if-not #'symbolp (list-all-slot-names node))
                           #'string<))
         (embedding (slot-value node 'embedding))
         (emb-bytes (when embedding
                      (serialize-embedding embedding precision))))
    (concatenate 'vector
                 (make-array (length slot-names) :element-type '(unsigned-byte 8)
                             :initial-element 0)) ; placeholder for slot name hashes
                 (or emb-bytes #(0)))))

(defun list-all-slot-names (node)
  "Return a list of all slot names defined on NODE's class."
  (mapcar 'slot-definition-name
          (remove-if-not #'(lambda (s)
                             (or (persistent-p s) (ephemeral-p s)))
                           (class-slots (class-of node)))))
;; --- Full node serialization round-trip ---

(defun serialize-node (node &key (precision :float32) (compressed-p nil))
  "Serialize a NODE to a byte vector including its embedding.
Returns: byte-vector containing [node-header] [slot-data] [embedding-data]"
  (let* ((slot-names (sort (remove-if-not #'symbolp (list-all-slot-names node))
                           #'string<))
         (embedding (slot-value node 'embedding))
         (emb-bytes (when embedding
                      (serialize-embedding embedding precision)))
         ;; Build header: slot count, embedding presence flag, precision tag
         (header (make-array 4 :element-type '(unsigned-byte 8)))
         (slot-data (make-array 0 :element-type '(unsigned-byte 8)
                                :adjustable t :fill-pointer t)))
    (setf (aref header 0) (length slot-names))
    (setf (aref header 1) (if embedding 1 0))
    (setf (aref header 2) (ecase precision
                            (float32 +embedding-float32+)
                            (float16 +embedding-float16+)
                            (bfloat16 +embedding-bfloat16+)
                            (int8 +embedding-int8+)))
    (setf (aref header 3) (if compressed-p 1 0))
    ;; Serialize each slot value (simplified - just placeholder)
    (loop for slot-name in slot-names
          do (let ((value (slot-value node slot-name)))
               (when value
                 (vector-push-extend 1 slot-data) ; placeholder
                 )))
    (concatenate 'vector header slot-data (or emb-bytes #(0)))))

(defun deserialize-node (bytes class &key (graph *graph*))
  "Deserialize a node from BYTES into an instance of CLASS.
Returns: node instance"
  (let* ((slot-count (aref bytes 0))
         (has-embedding (aref bytes 1))
         (precision-tag (aref bytes 2))
         (compressed-p (aref bytes 3))
         (precision (ecase precision-tag
                      (+embedding-float32+ 'float32)
                      (+embedding-float16+ 'float16)
                      (+embedding-bfloat16+ 'bfloat16)
                      (+embedding-int8+ 'int8)))
         (offset 4)
         (node (make-instance class)))
    ;; Deserialize slot data (simplified)
    (loop repeat slot-count
          do (incf offset)) ; skip placeholder
    ;; Deserialize embedding if present
    (when (and has-embedding (> (length bytes) offset))
      (let ((emb-bytes (subseq bytes offset)))
        (multiple-value-bind (vector dim prec)
            (deserialize-embedding emb-bytes)
          (setf (slot-value node 'embedding) vector)
          (setf (slot-value node 'embedding-dim) dim)
          (setf (slot-value node 'embedding-precision) prec)
          (setf (slot-value node 'embedding-compressed-p) compressed-p))))
    node))
