defmodule Playcode.Catalogue.Revision do
  @moduledoc """
  One change in a play's revision history, a TEI `revisionDesc/change`, as the files write
  it: its `date` as written ("2021"), the revisers' names (`people`, each a `persName`,
  "Muñoz Pons, Carlos"), the words saying what was done (`description`, "Revisión de la
  obra en formato TEI-XML"), and a `note` where a file says it in one (EMOTHE0090).
  Embedded in `plays.revisions`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Playcode.Text

  @primary_key false
  embedded_schema do
    field :date, :string
    field :people, {:array, :string}, default: []
    field :description, :string
    field :note, :string
  end

  def changeset(revision, attrs) do
    revision
    |> cast(attrs, [:date, :people, :description, :note])
    |> update_change(:date, &Text.squeeze/1)
    |> update_change(:description, &Text.squeeze/1)
    |> update_change(:note, &Text.squeeze/1)
  end
end
