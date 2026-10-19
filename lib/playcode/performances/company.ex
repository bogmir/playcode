defmodule Playcode.Performances.Company do
  @moduledoc """
  A company that staged plays: one record shared by every performance it gave, so
  renaming it renames it everywhere. Names are unique ignoring case.
  """

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "performance_companies" do
    field :name, :string

    timestamps(type: :utc_datetime)
  end
end
