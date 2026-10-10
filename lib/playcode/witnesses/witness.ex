defmodule Playcode.Witnesses.Witness do
  @moduledoc """
  One witness of a play's text: a manuscript or early printing, with the siglum an
  apparatus cites it by. `origin` works as for `Playcode.Catalogue.PlayEditor`;
  `filemaker_id` is set only by the import, on the struct, and `position` only by
  `Playcode.Witnesses`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  # The leaf of FileMaker's T03.1 tree; its "no consta" collapses into the parent.
  @types ~w(manuscript autograph copy early_edition collection collection_single_author
            collection_several_authors loose)

  @fields ~w(play_id siglum title normalized_title attribution pub_place publisher date
             format witness_type shelfmark note origin)a

  schema "play_witnesses" do
    field :siglum, :string
    field :title, :string
    field :normalized_title, :string
    field :attribution, :string
    field :pub_place, :string
    field :publisher, :string
    field :date, :string
    field :format, :string
    field :witness_type, :string
    field :shelfmark, :string
    field :note, :string
    field :position, :integer, default: 0
    field :origin, :string, default: "manual"
    field :filemaker_id, :string

    belongs_to :play, Playcode.Catalogue.Play

    timestamps(type: :utc_datetime)
  end

  def types, do: @types

  @doc "What a form and the imports may set."
  def changeset(witness, attrs) do
    witness
    |> cast(attrs, @fields)
    |> validate_required([:play_id])
    |> validate_inclusion(:witness_type, @types)
    |> validate_inclusion(:origin, Playcode.Catalogue.origins())
    |> validate_described()
    |> unique_constraint([:play_id, :siglum],
      error_key: :siglum,
      message: "is already used by another witness of this play"
    )
  end

  defp validate_described(changeset) do
    if Enum.any?([:title, :normalized_title, :note], &get_field(changeset, &1)),
      do: changeset,
      else: add_error(changeset, :title, "needs a title, a normalised title or a note")
  end
end
