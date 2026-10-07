defmodule Playcode.Bibliography.Link do
  @moduledoc """
  A play's link to a bibliography entry, with what belongs to that play alone: where it
  sits in a modern edition (`volume`, `pages`) and a `note` for researchers.

  `origin` is `"filemaker"` on a link the import made, which is how a re-run of the import
  knows the play is done, and `"manual"` otherwise.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "play_bibliography" do
    field :volume, :string
    field :pages, :string
    field :note, :string
    field :origin, :string, default: "manual"

    belongs_to :play, Playcode.Catalogue.Play
    belongs_to :entry, Playcode.Bibliography.Entry

    timestamps(type: :utc_datetime)
  end

  @doc "What a form may set. The play, the entry and `origin` are set on the struct."
  def changeset(link, attrs) do
    link
    |> cast(attrs, [:volume, :pages, :note])
    |> unique_constraint([:play_id, :entry_id],
      error_key: :entry_id,
      message: "is already linked to this play"
    )
    |> foreign_key_constraint(:entry_id)
    |> foreign_key_constraint(:play_id)
  end
end
