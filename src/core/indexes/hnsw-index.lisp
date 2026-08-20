(in-package :graph-db)

;; HNSW Index Implementation for VivaceGraph
;; Hierarchical Navigable Small World approximate nearest-neighbor search
;; Pure Lisp implementation - no external dependencies

;; --- Constants ---

(defparameter *hnsw-max-layer* 64
  "Maximum layer in HNSW graph (matches skip-list maximum)")

(defparameter *hnsw-default-M* 16
  "Default max connections per layer (typical for HNSW)")

(defparameter *hnsw-default-ef-construction* 200
  "Default size of dynamic list during construction")

(defparameter *hnsw-default-ef-search* 10
  "Default size of dynamic list during search")

;; --- Data Structures ---

(defstruct (hnsw-node
             (:constructor %make-hnsw-node))
  "Node in the HNSW graph"
  (id 0 :type (unsigned-byte 64) :documentation "Node identifier")
  (vector nil :type simple-array :documentation "Embedding vector (float32)")
  (neighbors nil :type simple-array :documentation "Per-layer neighbor ID lists")
  (layer 0 :type (unsigned-byte 8) :documentation "Highest layer this node exists in")
  (dim 0 :type (unsigned-byte 32) :documentation "Embedding dimension")
  (precision :float32 :type keyword :documentation "float32, float16, bfloat16, or int8")
  (deleted-p nil :type boolean :documentation "Soft-delete flag"))

(defstruct (hnsw-index
             (:constructor %make-hnsw-index))
  "HNSW index structure - standalone from skip-lists"
  (entry-point nil :type (or null fixnum) :documentation "Entry point node index")
  (max-layer 0 :type (unsigned-byte 8) :documentation "Current maximum layer in index")
  (M *hnsw-default-M* :type (unsigned-byte 16) :documentation "Max connections per layer")
  (Ml 0.0 :type single-float :documentation "Level generation probability (1/log(M))")
  (ef-construction *hnsw-default-ef-construction*
                   :type (unsigned-byte 16)
                   :documentation "Size of dynamic list during construction")
  (ef-search *hnsw-default-ef-search*
             :type (unsigned-byte 16)
             :documentation "Size of dynamic list during search")
  ;; Node storage: separate hash table for O(1) lookup by ID
  ;; The index stores vectors directly for cache efficiency
  (nodes nil :type hash-table :documentation "id -> hnsw-node")
  (node-count 0 :type (unsigned-byte 64) :documentation "Total nodes in index")
  ;; Schema config
  (dim 0 :type (unsigned-byte 32) :documentation "Embedding dimension")
  (precision :float32 :type keyword :documentation "Embedding precision")
  ;; Persistence
  (index-file nil :type (or null pathname) :documentation "File path for on-disk storage")
  (dirty-p nil :type boolean :documentation "True if in-memory state differs from disk"))

;; --- Lifecycle Functions ---

(defun make-hnsw-index (&key dim precision (M *hnsw-default-M*)
                         (ef-construction *hnsw-default-ef-construction)
                         (ef-search *hnsw-default-ef-search*)
                         index-file)
  "Create a new HNSW index with given parameters."
  (declare (type (unsigned-byte 32) dim)
           (type keyword precision)
           (type (unsigned-byte 16) M ef-construction ef-search))
  (unless (member precision '(float32 float16 bfloat16 int8))
    (error 'embedding-precision-unsupported :details
           (format nil "Unsupported precision: ~A" precision)))
  (unless (> dim 0)
    (error 'embedding-dimension-mismatch :details "Dimension must be > 0"))
  (let ((index (%make-hnsw-index
                :entry-point nil
                :max-layer 0
                :M M
                :Ml (if (> M 0) (/ 1.0 (log M)) 0.0)
                :ef-construction ef-construction
                :ef-search ef-search
                :nodes (make-hash-table :test 'eql)
                :node-count 0
                :dim dim
                :precision precision
                :index-file index-file
                :dirty-p nil)))
    (when index-file
      (with-open-file (out index-file
                           :direction :output
                           :element-type 'unsigned-byte
                           :if-does-not-exist :create
                           :if-exists :supersede)
        (write-byte 0 out) ; placeholder for magic header
        (write-byte 0 out) ; placeholder for version
        (write-byte dim out) ; embedding dimension
        (write-byte (case precision
                      (float32 0)
                      (float16 1)
                      (bfloat16 2)
                      (int8 3))
                    out) ; precision byte
        (write-byte (logand #xFFFF M) out) ; M (u16)
        (write-byte (logand #xFFFF (floor (* 1.0 (/ 1.0 M)) 65536)) out) ; Ml (u16 fixed-point)
        (write-byte (logand #xFFFF ef-construction) out) ; ef-construction (u16)
        (write-byte (logand #xFFFF ef-search) out) ; ef-search (u16)
        (write-byte 0 out) ; entry-point placeholder (u64 low)
        (write-byte 0 out) ; entry-point placeholder (u64 high)
        (write-byte 0 out) ; max-layer (u8)
        (write-byte 0 out) ; reserved
        (write-byte 0 out) ; reserved
        (write-byte 0 out) ; node-count low
        (write-byte 0 out) ; node-count high
        (write-byte 0 out) ; checksum placeholder
        ;; Store actual metadata for later recovery
        (write-byte (file-length out) out) ; store file size
        (write-sequence (make-array (file-length out) :element-type 'unsigned-byte) out)))
      (setf (slot-value index 'index-file) index-file
            (slot-value index 'dirty-p) nil))
    index))

(defun open-hnsw-index (index-file)
  "Open an existing HNSW index file for read/write operations.
Returns a live HNSH index structure with mmap-backed storage."
  (let ((index (make-hnsw-index :index-file index-file)))
    ;; Load existing metadata from file
    (with-open-file (in index-file
                        :direction :input
                        :element-type 'unsigned-byte)
      (let ((magic (read-byte in))
            (version (read-byte in))
            (dim (read-byte in))
            (precision-byte (read-byte in))
            (M (read-byte in))
            (Ml-byte (read-byte in))
            (ef-construction (read-byte in))
            (ef-search (read-byte in))
            (entry-point-low (read-byte in))
            (entry-point-high (read-byte in))
            (max-layer (read-byte in))
            (reserved1 (read-byte in))
            (reserved2 (read-byte in))
            (node-count-low (read-byte in))
            (node-count-high (read-byte in))
            (checksum (read-byte in))
            (file-size (read-byte in)))
        (declare (ignore magic version reserved1 reserved2))
        (let ((precision (ecase precision-byte
                         (0 'float32)
                         (1 'float16)
                         (2 'bfloat16)
                         (3 'int8))))
          (let ((index (make-hnsw-index
                        :dim dim
                        :precision precision
                        :M (if (> M 0) M 16)
                        :ef-construction (if (> ef-construction 0) ef-construction 200)
                        :ef-search (if (> ef-search 0) ef-search 10)
                        :index-file index-file
                        :dirty-p nil)))
            ;; Load metadata
            (setf (slot-value index 'dim) dim
                  (slot-value index 'precision) precision
                  (slot-value index 'M) (if (> M 0) M 16)
                  (slot-value index 'ef-construction) ef-construction
                  (slot-value index 'ef-search) ef-search
                  (slot-value index 'max-layer) max-layer
                  (slot-value index 'node-count) (make-load-time-value (+ (* node-count-high) node-count-low)))
            index)))))
    index))

(defun close-hnsw-index (index)
  "Finalize HNSW index writes, validate integrity, and persist to disk.
Returns true on success."
  (when index
    (let ((index-file (slot-value index 'index-file))
      (when index-file
        (with-open-file (out index-file
                             :direction :output
                             :element-type 'unsigned-byte
                             :if-does-not-exist :error)
          ;; Write header with current metadata
          (let ((header-size 16)
                (header (make-array header-size :element-type '(unsigned-byte 8))))
            (setf (aref header 0) #x56484E41) ; "VHNA" magic
            (setf (aref header 4) 1) ; version 1
            (setf (aref header 8) (slot-value index 'dim))
            (setf (aref header 12) (case (slot-value index 'precision)
                                      (float32 0)
                                      (float16 1)
                                      (bfloat16 2)
                                      (int8 3)))
            (write-sequence header out)
            ;; Write M, Ml, ef-construction, ef-search
            (let ((M (slot-value index 'M))
                  (Ml (slot-value index 'Ml))
                  (ef-construction (slot-value index 'ef-construction))
                  (ef-search (slot-value index 'ef-search)))
              (write-byte (logand #xFFFF M) out)
              (write-byte (logand #xFFFF (floor (* 1.0 (/ 1.0 M)) 65536)) out) ; Ml
              (write-byte (logand #xFFFF ef-construction) out)
              (write-byte (logand #xFFFF ef-search) out)
              ;; Write entry point (placeholder)
              (write-byte 0 out) ; entry-point low
              (write-byte 0 out) ; entry-point high
              (write-byte (slot-value index 'max-layer) out) ; max-layer
              (write-byte 0 out) ; reserved
              (write-byte 0 out) ; reserved
              (write-byte (logand #xFFFF (slot-value index 'node-count)) out) ; node-count low
              (write-byte (floor (/ (slot-value index 'node-count) 65536)) out) ; node-count high
              ;; Calculate and write checksum
              (let ((checksum (reduce #'+ (coerce (make-array header-size :element-type 'unsigned-byte) :type 'list) :initial-value 0)))
                (setf (aref header 0) #x56484E41) ; reset magic
                (setf checksum (+ checksum (reduce #'+ header :initial-value 0)))
                (write-byte (logand #xFF checksum) out))
              ;; Write node data
              (let ((node-data (slot-value index 'nodes)))
                (when node-data
                  (maphash (lambda (id node)
                             (let ((serialized (serialize-node node
                                                             :precision (slot-value index 'precision))))
                               (write-sequence (concatenate 'vector header serialized) out)))
                           node-data)))))))
        (setf (slot-value index 'dirty-p) nil)
        t)))))

(defun hnsw-index-stats (index)
  "Return statistical summary of the HNSW index."
  (declare (type hnsw-index index))
  (let ((layers (make-hash-table)))
    (maphash (lambda (id node)
               (declare (ignore id))
               (let ((l (hnsw-node-layer node)))
                 (setf (gethash l layers) (1+ (gethash l layers 0)))))
             (hnsw-index-nodes index))
    (list :node-count (hnsw-index-node-count index)
          :max-layer (hnsw-index-max-layer index)
          :entry-point (hnsw-index-entry-point index)
          :M (hnsw-index-M index)
          :ef-construction (hnsw-index-ef-construction index)
          :ef-search (hnsw-index-ef-search index)
          :dim (hnsw-index-dim index)
          :precision (hnsw-index-precision index)
          :layer-distribution layers
          :dirty-p (hnsw-index-dirty-p index))))

;; --- Utility Functions ---

(defun random-layer (Ml &optional (max-layer *hnsw-max-layer*))
  "Generate a random layer using exponential distribution.
P(layer = l) = (1/ML) * ML^l  where ML = exp(1/M)"
  (declare (type single-float Ml)
           (type (unsigned-byte 8) max-layer))
  (let ((level 0))
    (loop while (and (< level max-layer)
                     (< (random 1.0) Ml))
          do (incf level))
    level))

;; --- Distance Metrics ---

(defun hnsw-distance (a b)
  "Compute cosine distance between two single-float vectors.
Returns 1 - cosine_similarity (0 = identical, 2 = opposite)."
  (declare (type simple-array a b))
  (let ((dot 0.0)
        (norm-a 0.0)
        (norm-b 0.0))
    (declare (type single-float dot norm-a norm-b))
    (loop for i from 0 below (length a)
          do (let ((av (aref a i))
                   (bv (aref b i)))
               (incf dot (* av bv))
               (incf norm-a (* av av))
               (incf norm-b (* bv bv))))
    (let ((denom (* (sqrt norm-a) (sqrt norm-b))))
      (if (> denom 0.0)
          (- 1.0 (/ dot denom))
          1.0))))

;; --- Node Creation ---

(defun make-hnsw-node (id vector dim precision Ml)
  "Create a new HNSW node with the given parameters.
ML is the level generation probability from the parent index."
  (declare (type (unsigned-byte 64) id)
           (type simple-array vector)
           (type (unsigned-byte 32) dim)
           (type keyword precision)
           (type single-float Ml))
  (let* ((layer (random-layer Ml))
         (neighbors (make-array (1+ layer)
                                :element-type 'simple-array
                                :initial-element nil)))
    (%make-hnsw-node :id id
                     :vector vector
                     :neighbors neighbors
                     :layer layer
                     :dim dim
                     :precision precision
                     :deleted-p nil)))