(defpackage :graph-db/jsonl-demo  (:use #:cl #:graph-db))

(in-package :graph-db/jsonl-demo)

(defsystem graph-db/jsonl-demo
  :name "JSONL Import Demo"
  :version "0.1"
  :author "Emmanuel Rialland <first name dot last name @ gmail dot com>"
  :description "Import DB resources from JSONL data"
  :depends-on (:cl :uuidv7 :graph-db)
  :components ((:file "yago-import-demo")))

