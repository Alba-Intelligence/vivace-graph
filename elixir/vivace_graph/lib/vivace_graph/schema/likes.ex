defmodule VivaceGraph.Schema.Likes do
  use Ash.Resource, name: "Likes"

  attributes do
    attribute :weight, :float
  end

  actions do
    create :create
    update :update
    destroy :destroy
  end
end