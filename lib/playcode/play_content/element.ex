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
    * An `opener` is a division's opening formula, TEI's `<opener><salute>`: the *Arte
      nuevo*'s dedication, "Dirigido a la Academia de Madrid" (question 41).
    * `unrecognized` comes only from the Word importer.

  A speech's speakers are `element_characters`, kept in order, because `<sp who>` can
  name several. `characters/1` reads them, preloaded. `speaker_label` is the
  `<speaker>` text as printed.

  On a verse line:

    * `line_number` is `@n`.
    * `line_id` is `@xml:id`.
    * `part` (`I`, `M`, `F`) marks a verse split between speakers.
    * `verse_type` (redondilla, romance…) sits on the `line_group`.

  On a stage direction, `stage_type` is `@type`, the kind: one of `stage_types/0`, or
  any other word a file gives.

  `content` is plain text with italics as `<<…>>` markers and a stage direction inside a
  line or paragraph as `<stage type="…">…</stage>` (see `InlineMarkup`). A passage only the
  Folio prints is `<folio>…</folio>` (`InlineMarkup`), in a line's, a paragraph's or a stage
  direction's text, or a speech's `speaker_label`.
  `position` orders an element among its siblings.

  `is_aside` marks a line or paragraph spoken aside: all of it (`whole_aside?/1`), or,
  when its content holds `<aside>…</aside>` markers, the words inside them.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Playcode.PlayContent.InlineMarkup

  @stage_types ~w(setting entrance exit business novelistic delivery modifier location mixed)

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
    field :aside_continues, :boolean, default: false
    # Each aside piece's TEI attributes (xml:id, next), set by the TEI export alone.
    field :aside_links, {:array, :map}, virtual: true, default: []
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

  @doc "The kinds of stage direction TEI suggests for `<stage type>`, in its order."
  def stage_types, do: @stage_types

  @doc """
  Whether each aside piece of `element` starts an aside, in order. Its first piece does
  unless `aside_continues` says it continues the aside before it; each later piece, an
  `<aside>` marker, does when spoken words stand before it (a stage or a line's number is
  not spoken). A line all aside is one piece.
  """
  def aside_piece_starts(%{is_aside: true} = element) do
    first = not element.aside_continues

    if whole_aside?(element),
      do: [first],
      else: [first | later_piece_starts(element.content)]
  end

  def aside_piece_starts(_element), do: []

  @doc "How many asides start in `element` (`aside_piece_starts/1`)."
  def asides_started(element), do: element |> aside_piece_starts() |> Enum.count(& &1)

  defp later_piece_starts(content) do
    {starts, _spoken} =
      ~r{<aside>.*?</aside>}s
      |> Regex.split(content, include_captures: true, trim: true)
      |> Enum.drop_while(&(not String.starts_with?(&1, "<aside>")))
      |> Enum.drop(1)
      |> Enum.flat_map_reduce(false, fn
        "<aside>" <> _, spoken -> {[spoken], false}
        text, spoken -> {[], spoken or String.trim(InlineMarkup.spoken(text)) != ""}
      end)

    starts
  end

  @doc "True when every word of the element is spoken aside: no marker says which are."
  def whole_aside?(%{is_aside: aside, content: content}),
    do: aside and not String.contains?(content || "", "<aside>")

  @doc """
  True when every word of `element` is the Folio's alone (`InlineMarkup.whole_folio?/1`):
  a line's, a paragraph's or a stage direction's text; a speech's speaker label, if it has
  one, and all its parts; all a line group's lines. Readers who hide the Folio's passages
  see none of it.
  """
  def folio_only?(%{type: type} = element) when type in ~w(speech line_group) do
    children = children_of(element)
    label = Map.get(element, :speaker_label)

    children != [] and Enum.all?(children, &folio_only?/1) and
      (label in [nil, ""] or InlineMarkup.whole_folio?(label))
  end

  def folio_only?(element), do: InlineMarkup.whole_folio?(Map.get(element, :content))

  @doc "True when an element of `divisions`, as `PlayContent.load_play_content/2` gives them, holds a Folio passage."
  def folio_passages?(divisions) do
    Enum.any?(divisions, fn division ->
      Enum.any?(Map.get(division, :loaded_elements, []), &holds_folio?/1) or
        folio_passages?(children_of(division))
    end)
  end

  defp holds_folio?(element) do
    Enum.any?([element.content, element.speaker_label], &(&1 && String.contains?(&1, "<folio"))) or
      Enum.any?(children_of(element), &holds_folio?/1)
  end

  # What `load_play_content/2` loaded: a verse line's children are not.
  defp children_of(%{children: children}) when is_list(children), do: children
  defp children_of(_), do: []

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
      :aside_continues,
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
      ~w(speech stage_direction verse_line prose line_group opener trailer unrecognized)
    )
    |> validate_stage_markers()
    |> validate_aside_markers()
    |> validate_folio_markers()
    |> validate_number_markers()
    |> continue_only_an_aside()
  end

  # Only a line or paragraph spoken aside can continue an aside.
  defp continue_only_an_aside(changeset) do
    if get_field(changeset, :type) in ~w(verse_line prose) and get_field(changeset, :is_aside),
      do: changeset,
      else: put_change(changeset, :aside_continues, false)
  end

  # A Folio marker (InlineMarkup) is sound or refused, in the text of a line, a paragraph
  # or a stage direction, or a speech's speaker label: printed anywhere else it would show
  # its tags, and the export could not write it back.
  defp validate_folio_markers(changeset) do
    Enum.reduce(
      [content: ~w(verse_line prose stage_direction), speaker_label: ~w(speech)],
      changeset,
      fn {field, types}, changeset ->
        text = get_field(changeset, field)

        cond do
          not String.contains?(text || "", ["<folio", "</folio>"]) ->
            changeset

          get_field(changeset, :type) in types and
              InlineMarkup.folios_well_formed?(text) ->
            changeset

          true ->
            add_error(changeset, field, "has a Folio marker that is not well formed")
        end
      end
    )
  end

  # An aside marker, like a stage, is sound or refused, and only a line or a paragraph
  # holds one. A line holding one is an aside: the export writes the marker back only then.
  defp validate_aside_markers(changeset) do
    content = get_field(changeset, :content)

    cond do
      not String.contains?(content || "", ["<aside>", "</aside>"]) ->
        changeset

      get_field(changeset, :type) in ~w(verse_line prose) and
          Playcode.PlayContent.InlineMarkup.asides_well_formed?(content) ->
        put_change(changeset, :is_aside, true)

      true ->
        add_error(changeset, :content, "has an aside marker that is not well formed")
    end
  end

  # A malformed <lb would print as literal tags and could not be written back as <lb n>.
  # A bare <lb/> is refused too: a break is a newline in the text.
  defp validate_number_markers(changeset) do
    if changed?(changeset, :content) and
         not Playcode.PlayContent.InlineMarkup.numbers_well_formed?(
           get_field(changeset, :content)
         ),
       do: add_error(changeset, :content, "has a line number marker that is not well formed"),
       else: changeset
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
