defmodule Playcode.Performances.Performance do
  @moduledoc """
  One staging of a play recorded by a source: a date, a venue, a company, a cast. Spec:
  docs/superpowers/specs/2026-10-19-s5-performances-design.md.

  `date_text` is the date as the source wrote it ("c. 1620", "04/05//1674"); `year_from`
  and `year_to` are the years read from it (`years/1`), which the performances are ordered
  by. `venue` is the venue's name as the source gives it, text rather than a place; the town
  is `place`, and `historical_state` the state it belonged to then, as for a play's places.
  `position`, `origin` and `filemaker_id` work as for `Playcode.Witnesses.Witness`:
  `position` is set only by `Playcode.Performances` and `filemaker_id` only by the import.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Playcode.Performances.CastMember
  alias Playcode.Text

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  # FileMaker's T11.2, ids 1-8 in this order, with its Spanish and English labels. Here and
  # not in gettext: the static site prints them, and its fingerprint covers modules, not
  # the gettext backend.
  @venue_types [
    {"public_theatre", %{"es" => "teatro público", "en" => "public theatre"}},
    {"palace", %{"es" => "palacio", "en" => "palace / court"}},
    {"street", %{"es" => "calle, plaza", "en" => "street, square"}},
    {"other", %{"es" => "otro", "en" => "other"}},
    {"private_theatre", %{"es" => "teatro privado", "en" => "private theatre"}},
    {"unknown", %{"es" => "desconocido", "en" => "unknown"}},
    {"university",
     %{"es" => "universidad / “inns of court”", "en" => "university, inns of court"}},
    {"commercial_theatre", %{"es" => "teatro comercial", "en" => "commercial theatre"}}
  ]

  @labels Map.new(@venue_types)
  @types Enum.map(@venue_types, &elem(&1, 0))

  @fields ~w(play_id date_text year_from year_to venue venue_type company_id place_id
             historical_state_id note source_entry_id source_volume source_pages
             cast_from_cast_list origin)a

  @text ~w(date_text venue note source_volume source_pages)a

  @year_bounds [greater_than_or_equal_to: 1000, less_than_or_equal_to: 9999]

  # A performance says something when one of these is filled.
  @described ~w(date_text venue venue_type company_id note)a

  schema "play_performances" do
    field :date_text, :string
    field :year_from, :integer
    field :year_to, :integer
    field :venue, :string
    field :venue_type, :string
    field :note, :string
    field :source_volume, :string
    field :source_pages, :string
    field :cast_from_cast_list, :boolean, default: false
    field :position, :integer, default: 0
    field :origin, :string, default: "manual"
    field :filemaker_id, :string

    belongs_to :play, Playcode.Catalogue.Play
    belongs_to :company, Playcode.Performances.Company
    belongs_to :place, Playcode.Places.Place
    belongs_to :historical_state, Playcode.Places.Place
    belongs_to :source, Playcode.Bibliography.Entry, foreign_key: :source_entry_id

    has_many :cast, Playcode.Performances.CastMember,
      preload_order: [asc: :position],
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  def venue_types, do: @types

  @doc "The label of a venue type in `locale` (`\"es\"` or `\"en\"`), as FileMaker words it."
  def venue_type_label(type, locale), do: @labels[type][locale]

  @doc """
  The years a date as written gives, as `{from, to}`: every four-digit year in it, the
  smallest to the largest. A `-` and one or two digits right after a year complete it
  ("1597-9" is 1597 and 1599, "1610-11" 1610 and 1611) and "1590s" is 1590 and 1599. A date
  with a single year after "Before" has no beginning, `{nil, 1642}`; one with no year, none.
  """
  def years(nil), do: {nil, nil}

  def years(date) do
    case Enum.sort(Enum.uniq(whole_years(date) ++ completed_years(date) ++ decade_ends(date))) do
      [] -> {nil, nil}
      [year] -> if date =~ ~r/before\D*\d{4}/i, do: {nil, year}, else: {year, year}
      years -> {hd(years), List.last(years)}
    end
  end

  defp whole_years(date) do
    ~r/(?<!\d)\d{4}(?!\d)/
    |> Regex.scan(date)
    |> Enum.map(fn [year] -> String.to_integer(year) end)
  end

  defp completed_years(date) do
    for [year, tail] <-
          Regex.scan(~r/(?<!\d)(\d{4})-(\d{1,2})(?!\d)/, date, capture: :all_but_first) do
      scale = 10 ** String.length(tail)
      div(String.to_integer(year), scale) * scale + String.to_integer(tail)
    end
  end

  defp decade_ends(date) do
    for [decade] <- Regex.scan(~r/(?<!\d)(\d{3})0s/, date, capture: :all_but_first),
        do: String.to_integer(decade) * 10 + 9
  end

  @doc "What a form and the imports may set."
  def changeset(performance, attrs) do
    performance
    |> cast(attrs, @fields)
    |> squeeze(@text)
    |> drop_pages_without_source()
    |> validate_required([:play_id])
    |> validate_inclusion(:venue_type, @types)
    |> validate_inclusion(:origin, Playcode.Catalogue.origins())
    |> validate_described()
    |> fill_years()
    |> validate_years()
    |> unique_constraint(:cast_from_cast_list,
      name: :play_performances_one_cast_list_index,
      message: "is already set on another performance of this play"
    )
    |> foreign_key_constraint(:company_id)
    |> foreign_key_constraint(:place_id)
    |> foreign_key_constraint(:historical_state_id)
    |> foreign_key_constraint(:source_entry_id)
  end

  @doc """
  Replaces the cast with `rows` (`%{"actor_id" => id, "role" => role}`), in the order given.
  The performance must have its `cast` loaded.
  """
  def cast_changeset(performance, rows) do
    rows = Enum.with_index(rows, fn row, position -> Map.put(row, "position", position) end)

    performance
    |> cast(%{"cast" => rows}, [])
    |> cast_assoc(:cast, with: &CastMember.changeset/2)
  end

  # The volume and pages are where the performance sits in its source, and the TEI file writes
  # them inside the source's biblStruct: with no source they are meaningless, and dropped
  # rather than refused, which would lose the whole performance over them.
  defp drop_pages_without_source(changeset) do
    if get_field(changeset, :source_entry_id) do
      changeset
    else
      changeset |> put_change(:source_volume, nil) |> put_change(:source_pages, nil)
    end
  end

  # Line breaks and spaces as the TEI file gives them back (Playcode.Text.squeeze/1).
  defp squeeze(changeset, fields) do
    Enum.reduce(fields, changeset, fn field, cs -> update_change(cs, field, &Text.squeeze/1) end)
  end

  defp validate_described(changeset) do
    if Enum.any?(@described, &get_field(changeset, &1)),
      do: changeset,
      else: add_error(changeset, :date_text, "needs a date, a venue, a company or a note")
  end

  defp fill_years(changeset) do
    {from, to} = years(get_field(changeset, :date_text))
    {was_from, was_to} = years(changeset.data.date_text)

    changeset
    |> follow_date(:year_from, from, was_from)
    |> follow_date(:year_to, to, was_to)
  end

  # Four-digit years, as `years/1` reads them, which also keeps a typed one inside the column;
  # the last year is not before the first.
  defp validate_years(changeset) do
    changeset =
      Enum.reduce([:year_from, :year_to], changeset, &validate_number(&2, &1, @year_bounds))

    from = get_field(changeset, :year_from)
    to = get_field(changeset, :year_to)

    if from && to && to < from,
      do: add_error(changeset, :year_to, "must not be before the start year"),
      else: changeset
  end

  # A blank year takes the date's. So does one the date used to give, when the form sent it
  # back untouched along with a new date: it was never a curator's. One a curator set stays.
  defp follow_date(changeset, field, year, was) do
    current = get_field(changeset, field)

    if is_nil(current) or (current == was and not Map.has_key?(changeset.changes, field)),
      do: put_change(changeset, field, year),
      else: changeset
  end
end
