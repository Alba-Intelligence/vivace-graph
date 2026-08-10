(defpackage #:yago-import-demo
  (:use #:cl #:asdf))

(in-package #:yago-import-demo)

(defsystem yago-import-demo
  :name "Yago Import Demo"
  :version "0.1"
  :author "Emmanuel Rialland <first name dot last name @ gmail dot com>"
  :description "Import DB resources from the Yago version of Wikidata"
  :depends-on (:uuidv7 :graph-db)
  :components ((:file "yago-import-demo")))
