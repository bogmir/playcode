defmodule Playcode.Performances.Actor do
  @moduledoc """
  An actor named in a performance's cast, shared by every cast row that names them. A
  nickname stands for a name when there is no surname ("Molière", "Gros-René"); `sex` is
  `"man"`, `"woman"` or nil (FileMaker's "desconocido").
  """

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "performance_actors" do
    field :surname, :string
    field :forename, :string
    field :nickname, :string
    field :sex, :string

    timestamps(type: :utc_datetime)
  end
end
