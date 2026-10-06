defmodule Playcode.Catalogue.Play do
  use Ecto.Schema
  import Ecto.Changeset

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
    field :is_verse, :boolean, default: true
    field :form, :string
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
    field :edition_title, :string
    field :is_complete, :boolean, default: false
    field :historical_time, :string
    field :historical_time_note, :string
    field :composition_date_from, :integer
    field :composition_date_to, :integer
    field :composition_date_note, :string

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
    has_many :editorial_notes, Playcode.Catalogue.PlayEditorialNote
    has_many :characters, Playcode.PlayContent.Character
    has_many :divisions, Playcode.PlayContent.Division
    has_many :elements, Playcode.PlayContent.Element
    has_many :play_places, Playcode.Places.PlayPlace
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
    "pt" => "Português"
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

  @forms ~w(verse prose mixed)

  def forms, do: @forms

  @doc """
  The play's form as every page names it: the curator's choice when set, else "verse"
  when the text has any verse and "prose" otherwise. `is_verse` is recomputed from the
  verse lines on every import and content edit, so the automatic value follows the text;
  only a curator says "mixed".
  """
  def form(%__MODULE__{form: form}) when is_binary(form), do: form
  def form(%__MODULE__{is_verse: true}), do: "verse"
  def form(%__MODULE__{}), do: "prose"

  # The bounds on each composition year, deliberately wide — the corpus is 16th–17th
  # century, but the column is a year and a curator fixing a typo should not fight the
  # validator. Public so the TEI importer can reject an out-of-range attribute before
  # it reaches the changeset, where the failure would roll back the whole play.
  @composition_year_range 1000..2100

  def composition_year_range, do: @composition_year_range

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
      :is_verse,
      :form,
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
      :historical_time,
      :historical_time_note,
      :composition_date_from,
      :composition_date_to,
      :composition_date_note
    ])
    |> validate_required([:title, :code])
    |> validate_inclusion(:language, @valid_languages)
    |> validate_number(:verse_count, greater_than_or_equal_to: 0)
    |> validate_inclusion(:relationship_type, ~w(traduccion adaptacion refundicion))
    |> validate_inclusion(:form, @forms)
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
