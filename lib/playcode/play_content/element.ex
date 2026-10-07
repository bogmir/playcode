defmodule Playcode.PlayContent.Element do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "play_elements" do
    field :type, :string
    field :content, :string
    field :speaker_label, :string
    field :line_number, :integer
    field :line_id, :string
    field :verse_type, :string
    field :part, :string
    field :is_aside, :boolean, default: false
    field :rend, :string
    field :stage_type, :string
    field :position, :integer, default: 0

    belongs_to :play, Playcode.Catalogue.Play
    belongs_to :division, Playcode.PlayContent.Division
    belongs_to :parent, __MODULE__
    has_many :children, __MODULE__, foreign_key: :parent_id
    has_many :element_characters, Playcode.PlayContent.ElementCharacter

    many_to_many :characters, Playcode.PlayContent.Character,
      join_through: Playcode.PlayContent.ElementCharacter,
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  @doc """
  Returns the ordered list of characters from preloaded element_characters.
  """
  def characters(%__MODULE__{element_characters: ecs}) when is_list(ecs) do
    Enum.map(ecs, & &1.character)
  end

  def characters(%__MODULE__{}), do: []

  def changeset(element, attrs) do
    element
    |> cast(attrs, [
      :type,
      :content,
      :speaker_label,
      :line_number,
      :line_id,
      :verse_type,
      :part,
      :is_aside,
      :rend,
      :stage_type,
      :position,
      :play_id,
      :division_id,
      :parent_id
    ])
    |> validate_required([:type])
    |> validate_inclusion(
      :type,
      ~w(speech stage_direction verse_line prose line_group trailer unrecognized)
    )
  end
end
