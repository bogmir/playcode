defmodule Playcode.Performances.Company do
  @moduledoc """
  A company that staged plays: one record shared by every performance it gave, so
  renaming it renames it everywhere. Names are unique ignoring case.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Playcode.Text

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "performance_companies" do
    field :name, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(company, attrs) do
    company
    |> cast(attrs, [:name])
    |> update_change(:name, &Text.squeeze/1)
    |> validate_required([:name])
    |> unique_constraint(:name,
      name: :performance_companies_lower_name_index,
      message: "is already the name of another company"
    )
  end
end
