defmodule Playcode.Performances.CastMember do
  @moduledoc "One row of a performance's cast: an actor, the role they played, and its order."

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "performance_cast" do
    field :role, :string
    field :position, :integer, default: 0

    belongs_to :performance, Playcode.Performances.Performance
    belongs_to :actor, Playcode.Performances.Actor

    timestamps(type: :utc_datetime)
  end
end
