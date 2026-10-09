defmodule Playcode.PlayContent.Element do
  @moduledoc """
  One piece of a play's text. Elements form a tree through `parent_id`: a `speech`
  holds `line_group`s, which hold `verse_line`s, or it holds `prose` directly.
  Stage directions can sit at any level. Every element also carries its
  `division_id`, nested ones included.

  Other types:

    * A `prose` or `line_group` with no parent is text nobody speaks, such as a dumb
      show or a stanza that opens a prologue.
    * A `trailer` is a division's closing formula ("FIN DEL PRIMER ACTO"), exported
      last in its division.
    * `unrecognized` comes only from the Word importer.

  A speech's speakers are `element_characters`, kept in order, because `<sp who>` can
  name several. `characters/1` reads them, preloaded. `speaker_label` is the
  `<speaker>` text as printed.

  On a verse line:

    * `line_number` is `@n`.
    * `line_id` is `@xml:id`.
    * `part` (`I`, `M`, `F`) marks a verse split between speakers.
    * `verse_type` (redondilla, romance…) sits on the `line_group`.

  `content` is plain text with italics as `<<…>>` markers and a stage direction inside a
  line or paragraph as `<stage type="…">…</stage>` (see `InlineMarkup`).
  `position` orders an element among its siblings.
  """

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
    has_many :notes, Playcode.PlayContent.Note, preload_order: [asc: :offset, asc: :position]

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
    |> validate_stage_markers()
  end

  # A marker that is not closed, or is nested, would print as literal tags on every page
  # and could not be written back as <stage>. Only a verse line or a paragraph may hold
  # one: a stage direction or a trailer is a stage already, so a marker in it would be
  # counted twice and exported as <stage><stage>…</stage></stage>.
  defp validate_stage_markers(changeset) do
    if changed?(changeset, :content) or changed?(changeset, :type) do
      content = get_field(changeset, :content)

      sound? =
        if get_field(changeset, :type) in ~w(verse_line prose),
          do: Playcode.PlayContent.InlineMarkup.well_formed?(content),
          else: not String.contains?(content || "", ["<stage", "</stage>"])

      if sound?,
        do: changeset,
        else: add_error(changeset, :content, "has a stage marker that is not well formed")
    else
      changeset
    end
  end
end
