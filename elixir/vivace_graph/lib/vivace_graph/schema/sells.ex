defmodule VivaceGraph.Schema.Sells do
  use Ash.Resource, name: "Sells"

  attributes do
    attribute :weight, :float
  end

  actions do
    create :create
    update :update
    destroy :destroy
  end
end