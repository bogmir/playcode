defmodule Playcode.Catalogue.Play do
  @moduledoc """
  One edition of a play: its metadata. The text lives in `Playcode.PlayContent`.

  `code` (`EMOTHE0010`, `AL0001` for ARTELOPE) is how people and URLs name a play, and
  it is unique across archived plays too. `emothe_id` is the TEI header's
  `<idno type="EMOTHE">`, not the application.

  Plays form families. An original has a nil `relationship_type`. A translation,
  adaptation or later version (`relationship_types/0`) points at it through
  `parent_play_id`. A TEI file names the original by its `short_code/1`; while no
  play has that code, `pending_original_code` holds it, and
  `Catalogue.link_waiting_translations/0` links the two when the original arrives.

  `language` is the language the play is written in, from `<langUsage>` or the FileMaker
  index. It is not the TEI root's `xml:lang`, which is always "es".

  Who writes which column:

    * The TEI importer owns most of them. A re-import overwrites them in place.
    * The curators own the columns in `TeiImport`'s `@platform_owned`, which a
      re-import never touches.
    * `verse_count` and `auto_form` are derived from the text by
      `Catalogue.update_form_and_verse_count/1`. Read the play's form through `form/1`.
    * `deleted_at` and `content_version` are written only by the functions and the
      triggers named next to them.

  `is_complete` decides what the static site publishes. `show_variants` decides whether
  readers see the play's textual variants; like `is_complete` it is Playcode's, never written
  to or read from the TEI file. So is `team_note`, a text only staff read (question 58),
  printed nowhere.

  The numbering rule says how the play's numbers are counted: `numbering_type` what is
  numbered (`V` each verse; `VP` verses and prose paragraphs; `VL` verses and printed prose
  lines; `S` each speech), `numbering_restart` where the count starts again (`never`, at each
  `act`, at each `scene`), and `numbering_manual`, numbers typed by hand and never recounted.
  It is written to the TEI header's `refsDecl`. `number_label/2` is how a number is cited.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Playcode.Catalogue.Revision
  alias Playcode.Text

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "plays" do
    field :title, :string
    field :title_sort, :string
    field :code, :string
    field :language, :string, default: "es"
    field :author_name, :string
    field :author_sort, :string
    field :author_attribution, :string
    field :publication_date, :string
    field :verse_count, :integer
    field :auto_form, :string, default: "prose"
    field :form, :string
    field :numbering_type, :string, default: "V"
    field :numbering_restart, :string, default: "never"
    field :numbering_manual, :boolean, default: false
    field :publisher, :string
    field :pub_place, :string
    field :availability_note, :string
    field :project_description, :string
    field :editorial_declaration, :string
    field :original_title, :string
    field :licence_url, :string
    field :licence_text, :string
    field :emothe_id, :string
    field :sponsor, :string
    field :funder, :string
    field :authority, :string
    field :parent_play_id, :binary_id
    field :relationship_type, :string
    field :pending_original_code, :string
    field :edition_title, :string
    field :is_complete, :boolean, default: false
    field :show_variants, :boolean, default: true
    field :team_note, :string
    field :historical_time, :string
    field :historical_time_note, :string
    field :composition_date_from, :integer
    field :composition_date_to, :integer
    field :composition_date_note, :string
    field :edition_notes, {:array, :string}, default: []
    embeds_many :revisions, Revision, on_replace: :delete

    # Set only through Catalogue.delete_play/1 and restore_play/1 — deliberately absent
    # from every cast list so no form can archive a play.
    field :deleted_at, :utc_datetime

    # Moved by Postgres whenever something this play's static pages show changes
    # (migration 20261005120000_track_play_content_version). Never written from here.
    field :content_version, :integer, writable: :never, read_after_writes: true

    belongs_to :parent_play, Playcode.Catalogue.Play, define_field: false
    has_many :derived_plays, Playcode.Catalogue.Play, foreign_key: :parent_play_id

    has_many :editors, Playcode.Catalogue.PlayEditor
    has_many :sources, Playcode.Catalogue.PlaySource
    has_many :paratexts, Playcode.Catalogue.Paratext
    has_many :characters, Playcode.PlayContent.Character
    has_many :divisions, Playcode.PlayContent.Division
    has_many :elements, Playcode.PlayContent.Element
    has_many :play_places, Playcode.Places.PlayPlace
    has_many :witnesses, Playcode.Witnesses.Witness
    has_many :performances, Playcode.Performances.Performance
    has_one :statistic, Playcode.Statistics.PlayStatistic

    timestamps(type: :utc_datetime)
  end

  @valid_languages ~w(es en it ca fr pt)

  def valid_languages, do: @valid_languages

  @language_names %{
    "es" => "Español",
    "en" => "English",
    "it" => "Italiano",
    "ca" => "Català",
    "fr" => "Français",
    "pt" => "Português",
    "de" => "Deutsch"
  }

  def language_name(code), do: Map.get(@language_names, code, code)

  # FileMaker bus_tiemHistorico codes, recovered by pairing the code against the rendered
  # label across all 439 rows of the export. Codes 3 and 4 do not occur.
  #   1 tiempo_indeterminado   2 antiguo_testamento   5 edad_media
  #   6 siglo_xv               7 siglo_xvi            8 siglo_xvii
  #   9 tiempo_maravilloso    10 antiguedad_clasica  11 tiempo_alegorico
  @historical_times ~w(
    tiempo_indeterminado antiguo_testamento edad_media siglo_xv siglo_xvi
    siglo_xvii tiempo_maravilloso antiguedad_clasica tiempo_alegorico
  )

  def historical_times, do: @historical_times

  @forms ~w(verse occasional_verse prose mixed)
  @numbering_types ~w(V VP VL S)
  @numbering_restarts ~w(never act scene)

  @doc "What a numbering rule numbers: `numbering_type`'s values."
  def numbering_types, do: @numbering_types

  @doc "Where a numbering rule's count starts again: `numbering_restart`'s values."
  def numbering_restarts, do: @numbering_restarts

  @doc """
  The word a number is cited with, by the play's numbering type: a verse's (`:verse`), a prose
  paragraph's or printed line's (`:prose`), a range of verse numbers (`:range`). Placeholders
  until the researcher picks the words.
  """
  def number_label(%{numbering_type: "S"}, _kind), do: "int."
  def number_label(_play, :prose), do: "l."
  def number_label(_play, :range), do: "vv."
  def number_label(_play, :verse), do: "v."

  def forms, do: @forms

  @doc """
  The play's form as every page names it: the curator's choice when set, else the one
  worked out from the text (`auto_form/2`), which every import and content edit
  recomputes. Only a curator says "mixed" (question 23).
  """
  def form(%__MODULE__{form: form}) when is_binary(form), do: form
  def form(%__MODULE__{auto_form: auto_form}), do: auto_form

  # ponytail: question 23 still asks where verse and prose ends (proposed nine tenths);
  # until it is answered, over a tenth is verse and "mixed" only a curator's choice.
  @occasional_share 0.1

  @doc """
  The form a text's verse and prose give, by the length of each (question 23): no verse
  is prose, under a tenth of the text in verse prose with occasional verse, more verse.
  """
  def auto_form(0, _prose_length), do: "prose"

  def auto_form(verse_length, prose_length) do
    if verse_length < @occasional_share * (verse_length + prose_length),
      do: "occasional_verse",
      else: "verse"
  end

  @file_labels %{
    "verse" => "verso",
    "occasional_verse" => "prosaverso",
    "prose" => "prosa",
    "mixed" => "versoprosa"
  }

  @doc "A form as the EMOTHE files label it on `extent/@ana` (question 22): `verso`…"
  def file_label(form), do: Map.fetch!(@file_labels, form)

  @doc "The form a file's `extent/@ana` names, or nil for any other word."
  def form_of_file_label(label),
    do: Enum.find_value(@file_labels, fn {form, word} -> if word == label, do: form end)

  @doc """
  The part of a code before its first `_`: `EMOTHE0530` of
  `EMOTHE0530_LesAmoursTragiquesDePyrameEtThisbe`. It is what names a play for FileMaker
  and across versions of its file, whose readable tail may change, so a TEI file names a
  play's original by it.
  """
  def short_code(nil), do: nil
  def short_code(code), do: code |> String.split("_", parts: 2) |> hd()

  @doc "The composition years as printed: `1614`, `1600–1601`, or nil with none."
  def composition_years(%{composition_date_from: nil}), do: nil

  def composition_years(%{composition_date_from: from, composition_date_to: to})
      when to in [nil, from],
      do: "#{from}"

  def composition_years(%{composition_date_from: from, composition_date_to: to}),
    do: "#{from}–#{to}"

  # The bounds on each composition year, deliberately wide — the corpus is 16th–17th
  # century, but the column is a year and a curator fixing a typo should not fight the
  # validator. Public so the TEI importer can reject an out-of-range attribute before
  # it reaches the changeset, where the failure would roll back the whole play.
  @composition_year_range 1000..2100

  def composition_year_range, do: @composition_year_range

  @relationship_types ~w(traduccion adaptacion version)

  @doc """
  The kinds of play made from another, as a TEI file's main title names them
  (`<title type="adaptacion">`): the values of `relationship_type`. A `version` is a later
  version of a play (question 40). A refundición is an adaptation (question 15).
  """
  def relationship_types, do: @relationship_types

  def changeset(play, attrs) do
    play
    |> cast(attrs, [
      :title,
      :title_sort,
      :code,
      :language,
      :author_name,
      :author_sort,
      :author_attribution,
      :publication_date,
      :verse_count,
      :auto_form,
      :form,
      :numbering_type,
      :numbering_restart,
      :numbering_manual,
      :publisher,
      :pub_place,
      :availability_note,
      :project_description,
      :editorial_declaration,
      :original_title,
      :licence_url,
      :licence_text,
      :emothe_id,
      :sponsor,
      :funder,
      :authority,
      :parent_play_id,
      :relationship_type,
      :edition_title,
      :is_complete,
      :show_variants,
      :team_note,
      :historical_time,
      :historical_time_note,
      :composition_date_from,
      :composition_date_to,
      :composition_date_note,
      :edition_notes
    ])
    |> update_change(:edition_notes, &squeeze_notes/1)
    |> cast_embed(:revisions, sort_param: :revisions_order, drop_param: :revisions_delete)
    |> validate_required([:title, :code])
    |> validate_inclusion(:language, @valid_languages)
    |> validate_number(:verse_count, greater_than_or_equal_to: 0)
    |> validate_inclusion(:relationship_type, @relationship_types)
    |> validate_inclusion(:form, @forms)
    |> validate_inclusion(:numbering_type, @numbering_types)
    |> validate_inclusion(:numbering_restart, @numbering_restarts)
    |> validate_inclusion(:historical_time, @historical_times)
    |> validate_number(:composition_date_from,
      greater_than_or_equal_to: @composition_year_range.first,
      less_than_or_equal_to: @composition_year_range.last
    )
    |> validate_number(:composition_date_to,
      greater_than_or_equal_to: @composition_year_range.first,
      less_than_or_equal_to: @composition_year_range.last
    )
    |> validate_composition_date_span()
    |> unique_constraint(:code)
  end

  # A note left blank, in the file or the form, is no note.
  defp squeeze_notes(notes), do: notes |> Enum.map(&Text.squeeze/1) |> Enum.reject(&is_nil/1)

  # Both endpoints or neither: a lone year is a half-filled form, not a dating.
  defp validate_composition_date_span(changeset) do
    from = get_field(changeset, :composition_date_from)
    to = get_field(changeset, :composition_date_to)

    cond do
      is_nil(from) and is_nil(to) ->
        changeset

      is_nil(to) ->
        add_error(changeset, :composition_date_from, "must be given together with the end year")

      is_nil(from) ->
        add_error(changeset, :composition_date_to, "must be given together with the start year")

      from > to ->
        add_error(changeset, :composition_date_to, "must not be before the start year")

      true ->
        changeset
    end
  end

  @doc """
  Changeset for manual form entry.
  """
  def form_changeset(play, attrs) do
    changeset(play, attrs)
  end
end
