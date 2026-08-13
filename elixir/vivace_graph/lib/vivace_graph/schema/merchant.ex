defmodule VivaceGraph.Schema.Merchant do
  use Ash.Resource, name: "Merchant"

  attributes do
    attribute :name, :string
    attribute :location, :string
  end

  actions do
    create :create
    update :update
    destroy :destroy
  end
end