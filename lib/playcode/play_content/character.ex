defmodule Playcode.PlayContent.Character do
  @moduledoc """
  A character in the play's cast list (`<castList>`).

  `xml_id` is the identifier speeches cite: `<sp who="#don_diego">`. It is unique within
  the play. `description` is the `<roleDesc>`; `actor` the `<actor>` who played the part
  at the first performance, kept and written back but printed nowhere, as emothe.uv.es
  prints none (question 28). `position` is the order in the cast list.

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
