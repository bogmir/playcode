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

  alias Playcode.PlayContent.{Division, Element, InlineMarkup}

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

  @doc """
  The notes in `divisions` (as `PlayContent.load_play_content/1` gives them) in reading
  order: a division's heading, its own text, then its scenes; an element's own notes (a
  speech's, on its speaker), then its children's. Note numbers follow this order.
  """
  def reading_order(divisions) when is_list(divisions),
    do: Enum.flat_map(divisions, &reading_order/1)

  def reading_order(%Division{} = division) do
    division.notes ++
      Enum.flat_map(division.loaded_elements, &element_notes/1) ++
      reading_order(loaded(division.children))
  end

  defp element_notes(%Element{} = element),
    do: element.notes ++ Enum.flat_map(loaded(element.children), &element_notes/1)

  defp loaded(%Ecto.Association.NotLoaded{}), do: []
  defp loaded(list), do: list

  @doc """
  Where a note can go in `text`: after each word, as `{word, offset}`, a repeated word
  numbered ("partes (2)"). The offset counts graphemes of the plain text.
  """
  def word_ends(text) do
    plain = InlineMarkup.plain(text)

    {ends, _seen} =
      ~r/[\p{L}\p{N}'’]+/u
      |> Regex.scan(plain, return: :index)
      |> Enum.map_reduce(%{}, fn [{start, length}], seen ->
        word = binary_part(plain, start, length)
        count = Map.get(seen, word, 0) + 1
        label = if count == 1, do: word, else: "#{word} (#{count})"
        offset = String.length(binary_part(plain, 0, start + length))
        {{label, offset}, Map.put(seen, word, count)}
      end)

    ends
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
    |> foreign_key_constraint(:element_id)
    |> foreign_key_constraint(:division_id)
  end
end
