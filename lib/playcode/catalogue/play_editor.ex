defmodule Playcode.Catalogue.PlayEditor do
  @moduledoc """
  A person credited on the edition, by `role` (translator, editor, reviewer…), in display
  order. `origin` says who wrote the row: a TEI re-import replaces only its own (`"tei"`)
  and keeps what a researcher typed.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "play_editors" do
    field :person_name, :string
    field :role, :string
    field :organization, :string
    field :position, :integer, default: 0
    field :origin, :string, default: "manual"

    belongs_to :play, Playcode.Catalogue.Play

    timestamps(type: :utc_datetime)
  end

  def changeset(editor, attrs) do
    editor
    |> cast(attrs, [:person_name, :role, :organization, :position, :play_id, :origin])
    |> validate_required([:person_name, :role])
    |> validate_inclusion(
      :role,
      ~w(editor digital_editor reviewer principal translator researcher critical_editor)
    )
    |> validate_inclusion(:origin, Playcode.Catalogue.origins())
  end

  @doc """
  The name forename first, as readers see it: "Ros Ferrer, Violeta" is "Violeta Ros
  Ferrer". A name with no comma, more than one, or a parenthesis is printed as written.
  """
  def display_name(%{person_name: name}) do
    case String.split(name, ", ") do
      [surname, forename] when surname != "" and forename != "" ->
        if String.contains?(name, "("), do: name, else: "#{forename} #{surname}"

      _ ->
        name
    end
  end

  @doc "The editors grouped by role, each role where its first editor stands: `[{role, editors}]`."
  def by_role(editors) do
    editors
    |> Enum.group_by(& &1.role)
    |> Enum.sort_by(fn {_role, [first | _]} -> Enum.find_index(editors, &(&1 == first)) end)
  end
end
