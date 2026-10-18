defmodule Playcode.Catalogue.Revision do
  @moduledoc """
  One change in a play's revision history, a TEI `revisionDesc/change`, as the files write
  it: its `date` as written ("2021"), the revisers (`people`, each a `persName` in the file,
  joined with "; " as a bibliography field's people are: "Muñoz Pons, Carlos; Tronch Pérez,
  Jesús"), the words saying what was done (`description`, "Revisión de la
  obra en formato TEI-XML"), and a `note` where a file says it in one (EMOTHE0090).
  Embedded in `plays.revisions`, edited in the play form.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Playcode.Text

  @primary_key false
  embedded_schema do
    field :date, :string
    field :people, :string
    field :description, :string
    field :note, :string
  end

  def changeset(revision, attrs) do
    revision
    |> cast(attrs, [:date, :people, :description, :note])
    |> update_change(:date, &Text.squeeze/1)
    |> update_change(:people, &Text.squeeze/1)
    |> update_change(:description, &Text.squeeze/1)
    |> update_change(:note, &Text.squeeze/1)
  end

  @doc "Whether a change says nothing: a row of the play form left empty is no change."
  def blank?(params),
    do: Enum.all?(~w(date people description note), &(Text.squeeze(params[&1]) == nil))
end
