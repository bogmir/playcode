defmodule Playcode.PlayContent.Note do
  @moduledoc """
  An editor's or translator's gloss on one word of the play text: a TEI `<note>` in the
  body. It hangs on an element (a verse line, a prose paragraph, a stage direction, a
  trailer, or a speech, whose note is on its speaker label) or on a division's heading,
  `offset` graphemes into that text's plain form (`InlineMarkup.plain/1`, so the `<<…>>`
  markers do not count). `position` orders the notes at one offset.

  `n` is the source's number, kept for the TEI export and never shown: readers see
  `number`, which `PlayContent.load_play_content/1` fills in reading order. `type` is
  TEI's (`types/0` lists the corpus's); the importer keeps whatever the file says.
  `body` is paragraphs separated by a blank line, italics as `<<…>>`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @types ~w(traductor editor editor_critico editor_digital autor)

  schema "play_notes" do
    field :offset, :integer
    field :position, :integer, default: 0
    field :n, :string
    field :type, :string
    field :term, :string
    field :body, :string
    field :number, :integer, virtual: true

    belongs_to :play, Playcode.Catalogue.Play
    belongs_to :element, Playcode.PlayContent.Element
    belongs_to :division, Playcode.PlayContent.Division

    timestamps(type: :utc_datetime)
  end

  @doc "The note types the corpus uses, as TEI spells them."
  def types, do: @types

  @doc "The note's paragraphs, in order."
  def paragraphs(%__MODULE__{body: body}) do
    body
    |> String.split(~r/\n\s*\n/)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  def changeset(note, attrs) do
    note
    |> cast(attrs, [
      :offset,
      :position,
      :n,
      :type,
      :term,
      :body,
      :play_id,
      :element_id,
      :division_id
    ])
    |> validate_required([:offset, :body, :play_id])
    |> validate_number(:offset, greater_than_or_equal_to: 0)
    |> check_constraint(:element_id, name: :one_anchor)
  end
end
