defmodule VivaceGraph.Schema.Person do
  use Ash.Resource, name: "Person"

  attributes do
    attribute :first_name, :string
    attribute :middle_name, :string
    attribute :last_name, :string
  end

  actions do
    create :create
    update :update
    destroy :destroy
  end
end