defmodule Playcode.PlayContent.CastListEntry do
  @moduledoc """
  One line of one cast list (a `<castItem>`), holding what that list prints: its `name`
  and `description` exactly as the list gives them (a play may name a person differently
  from one list to the next), and its `group_heading`, the `<castGroup>` it stands in.
  Consecutive entries with the same heading are one group.

  `character_id` is the person the speeches point at, or nil for a line that names no one
  who speaks ("Servants and attendants"). A character's first entry in outline order
  declares it (`<role xml:id>`); every later one refers to it (`<role corresp>`).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "cast_list_entries" do
    field :name, :string
    field :description, :string
    field :group_heading, :string
    field :position, :integer, default: 0

    belongs_to :play, Playcode.Catalogue.Play
    belongs_to :cast_list, Playcode.PlayContent.Division
    belongs_to :character, Playcode.PlayContent.Character

    timestamps(type: :utc_datetime)
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [
      :name,
      :description,
      :group_heading,
      :position,
      :play_id,
      :cast_list_id,
      :character_id
    ])
    |> validate_required([:name, :play_id, :cast_list_id])
  end

  @doc """
  What a printed cast list shows of its `entries` (each with its `:character` loaded): a
  hidden character's left out, the rest in runs that share a group heading.
  """
  def printed_groups(entries) do
    entries
    |> Enum.reject(&match?(%{character: %{is_hidden: true}}, &1))
    |> Enum.chunk_by(& &1.group_heading)
  end
end
