defmodule VivaceGraph.Schema.Customer do
  use Ash.Resource, name: "Customer"

  attributes do
    attribute :email, :string
  end

  actions do
    create :create
    update :update
    destroy :destroy
  end
end