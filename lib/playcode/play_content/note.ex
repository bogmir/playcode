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

  # A word a note can follow: letters and digits, an apostrophe inside.
  @word ~r/[\p{L}\p{N}'’]+/u

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
  def reading_order(divisions), do: divisions |> with_anchors() |> Enum.map(& &1.note)

  @doc """
  `reading_order/1` with where each note is: `%{note, anchor, division, scene}`, `anchor`
  the element or division it hangs on, `division` the top-level division of `divisions`
  and `scene` its child holding the note, or nil.
  """
  def with_anchors(divisions) when is_list(divisions),
    do: Enum.flat_map(divisions, &with_anchors/1)

  def with_anchors(%Division{} = division), do: division_notes(division, division, nil)

  defp division_notes(anchor, division, scene) do
    at = %{division: division, scene: scene}

    Enum.map(anchor.notes, &Map.merge(at, %{note: &1, anchor: anchor})) ++
      Enum.flat_map(anchor.loaded_elements, &element_notes(&1, at)) ++
      Enum.flat_map(loaded(anchor.children), &division_notes(&1, division, &1))
  end

  defp element_notes(%Element{} = element, at) do
    Enum.map(element.notes, &Map.merge(at, %{note: &1, anchor: element})) ++
      Enum.flat_map(loaded(element.children), &element_notes(&1, at))
  end

  defp loaded(%Ecto.Association.NotLoaded{}), do: []
  defp loaded(list), do: list

  @doc """
  The word a note glosses: its `term`, or else the last word of `text` (the text it hangs
  on, as `PlayContent.anchor_text/1` gives it) before its offset, or nil when there is none.
  """
  def glossed(%__MODULE__{term: term}, _text) when is_binary(term) and term != "", do: term

  def glossed(%__MODULE__{offset: offset}, text) do
    before = text |> InlineMarkup.plain() |> String.slice(0, offset)

    case Regex.scan(@word, before) do
      [] -> nil
      words -> words |> List.last() |> hd()
    end
  end

  @doc """
  Where a note can go in `text`: after each word, as `{word, offset}`, a repeated word
  numbered ("partes (2)"). The offset counts graphemes of the plain text.
  """
  def word_ends(text) do
    plain = InlineMarkup.plain(text)

    {ends, _seen} =
      @word
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
