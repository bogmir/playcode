defmodule Playcode.Catalogue.PlayEditorialNote do
  @moduledoc """
  A front-matter text by `section_type`: an editor's introduction, a dedication, an
  argument, a prologue or a note, with an optional `heading`. `origin` works as for
  `PlayEditor`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "play_editorial_notes" do
    field :section_type, :string
    field :heading, :string
    field :content, :string
    field :position, :integer, default: 0
    field :origin, :string, default: "manual"

    belongs_to :play, Playcode.Catalogue.Play

    timestamps(type: :utc_datetime)
  end

  def changeset(note, attrs) do
    note
    |> cast(attrs, [:section_type, :heading, :content, :position, :play_id, :origin])
    |> validate_required([:section_type, :content])
    |> validate_inclusion(
      :section_type,
      ~w(introduccion_editor dedicatoria argumento prologo nota)
    )
    |> validate_inclusion(:origin, Playcode.Catalogue.origins())
  end
end
