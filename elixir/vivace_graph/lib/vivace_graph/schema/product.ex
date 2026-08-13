defmodule VivaceGraph.Schema.Product do
  use Ash.Resource, name: "Product"

  attributes do
    attribute :name, :string
    attribute :upc, :string
  end

  actions do
    create :create
    update :update
    destroy :destroy
  end
end