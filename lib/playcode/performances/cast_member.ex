defmodule Playcode.Performances.CastMember do
  @moduledoc "One row of a performance's cast: an actor, the role they played, and its order."

  use Ecto.Schema
  import Ecto.Changeset

  alias Playcode.Text

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "performance_cast" do
    field :role, :string
    field :position, :integer, default: 0

    belongs_to :performance, Playcode.Performances.Performance
    belongs_to :actor, Playcode.Performances.Actor

    timestamps(type: :utc_datetime)
  end

  @doc "A row of the cast `Playcode.Performances.put_cast/2` replaces: an actor, and perhaps a role."
  def changeset(member, attrs) do
    member
    |> cast(attrs, [:actor_id, :role, :position])
    |> update_change(:role, &Text.squeeze/1)
    |> validate_required([:actor_id])
    |> validate_change(:actor_id, &validate_uuid/2)
    |> foreign_key_constraint(:actor_id)
  end

  # `:binary_id` casts any binary, and a malformed one would raise when dumped.
  defp validate_uuid(field, id) do
    case Ecto.UUID.cast(id) do
      {:ok, _} -> []
      :error -> [{field, "is invalid"}]
    end
  end
end
