defmodule Playcode.PlayContent.ElementCharacter do
  @moduledoc """
  Who speaks a speech: one row per character, in the order of TEI's `<sp who="#A #B">`.
  Deleting the speech or the character deletes the row.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "element_characters" do
    belongs_to :element, Playcode.PlayContent.Element
    belongs_to :character, Playcode.PlayContent.Character
    field :position, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  def changeset(element_character, attrs) do
    element_character
    |> cast(attrs, [:element_id, :character_id, :position])
    |> validate_required([:element_id, :character_id])
    |> unique_constraint([:element_id, :character_id])
  end
end
