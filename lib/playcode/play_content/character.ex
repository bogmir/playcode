defmodule Playcode.PlayContent.Character do
  @moduledoc """
  A character in the play's cast list (`<castList>`).

  `xml_id` is the identifier speeches cite: `<sp who="#don_diego">`. It is unique within
  the play. Each cast list naming the character holds an entry of its own
  (`Playcode.PlayContent.CastListEntry`); `name`, `description` (the `<roleDesc>`) and
  `position` are copies of its first entry's in outline order, kept in step by
  `PlayContent.sync_characters/1`, for wherever Playcode names a speaker. `actor` is the
  `<actor>` who played the part at the first performance, kept and written back but
  printed nowhere, as emothe.uv.es prints none (question 28).

  A hidden character (`is_hidden`, TEI `ana="oculto"`) may speak, but every printed cast
  list leaves it out.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Playcode.Text

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "characters" do
    field :xml_id, :string
    field :name, :string
    field :description, :string
    field :actor, :string
    field :is_hidden, :boolean, default: false
    field :position, :integer, default: 0

    belongs_to :play, Playcode.Catalogue.Play
    has_many :element_characters, Playcode.PlayContent.ElementCharacter
    has_many :entries, Playcode.PlayContent.CastListEntry

    many_to_many :elements, Playcode.PlayContent.Element,
      join_through: Playcode.PlayContent.ElementCharacter

    timestamps(type: :utc_datetime)
  end

  def changeset(character, attrs) do
    character
    |> cast(attrs, [:xml_id, :name, :description, :actor, :is_hidden, :position, :play_id])
    |> update_change(:actor, &Text.squeeze/1)
    |> validate_required([:xml_id, :name])
    |> unique_constraint([:play_id, :xml_id],
      error_key: :xml_id,
      message: "is already in use for this play"
    )
  end
end
