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

  @fields [:date, :people, :description, :note]

  @primary_key false
  embedded_schema do
    field :date, :string
    field :people, :string
    field :description, :string
    field :note, :string
  end

  def changeset(revision, attrs) do
    changeset = cast(revision, attrs, @fields)
    Enum.reduce(@fields, changeset, fn field, cs -> update_change(cs, field, &Text.squeeze/1) end)
  end
end
