defmodule Playcode.Places.Place do
  @moduledoc """
  A place: one stable referent, real or fictional.

  Deliberately has **no name column** — every surface form lives in `place_names`,
  because a denormalised copy and its child row have no constraint keeping them in
  step and drift silently. `Playcode.Places.display_name/2` picks the one to show.

  Containment is `parent_place_id`, and depth is opportunistic: a place may have no
  parent at all. "Woods in Transylvania" is a row with a parent, no coordinates and a
  note — absent coordinates are what say "not pinned", so there is no extra column for
  it. `is_fictional` means something narrower: no real referent, as in Atlántida.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  # One axis only: every term answers "what kind of geographic feature is this".
  # `port` was rejected because it describes a function, not a feature class, and
  # Naples is both a city and a port. Adding a term is three lines; removing one is a
  # data migration, so the list errs toward too few.
  @types ~w(continent country province region district city town
            building forest river lake sea island mountain other)

  @authorities ~w(wikidata geonames tgn pleiades)

  def types, do: @types
  def authorities, do: @authorities

  schema "places" do
    field :slug, :string
    field :type, :string
    field :latitude, :float
    field :longitude, :float
    field :is_fictional, :boolean, default: false
    field :authority, :string
    field :authority_id, :string
    field :note, :string

    field :play_count, :integer, virtual: true

    belongs_to :parent, __MODULE__, foreign_key: :parent_place_id
    has_many :children, __MODULE__, foreign_key: :parent_place_id
    has_many :names, Playcode.Places.PlaceName, on_replace: :delete
    has_many :play_places, Playcode.Places.PlayPlace

    has_many :state_links, Playcode.Places.PlayPlace, foreign_key: :historical_state_id

    timestamps(type: :utc_datetime)
  end

  def changeset(place, attrs) do
    place
    |> cast(attrs, [
      :slug,
      :type,
      :parent_place_id,
      :latitude,
      :longitude,
      :is_fictional,
      :authority,
      :authority_id,
      :note
    ])
    |> validate_required([:slug, :type])
    |> validate_inclusion(:type, @types)
    |> validate_inclusion(:authority, @authorities)
    |> validate_number(:latitude, greater_than_or_equal_to: -90, less_than_or_equal_to: 90)
    |> validate_number(:longitude, greater_than_or_equal_to: -180, less_than_or_equal_to: 180)
    |> validate_not_self_parent()
    |> unique_constraint(:slug)
    |> unique_constraint([:authority, :authority_id],
      name: :places_authority_authority_id_index,
      error_key: :authority_id,
      message: "is already linked to another place"
    )
    |> foreign_key_constraint(:parent_place_id)
  end

  defp validate_not_self_parent(changeset) do
    case {get_field(changeset, :id), get_change(changeset, :parent_place_id)} do
      {id, id} when not is_nil(id) -> add_error(changeset, :parent_place_id, "cannot be itself")
      _ -> changeset
    end
  end
end
