defmodule Playcode.Catalogue.PlaySource do
  @moduledoc """
  A printed source the digital edition was made from, TEI's `<sourceDesc><bibl>`. Most
  corpus files carry the citation as free text in `note`; the structured fields are
  optional. `origin` works as for `PlayEditor`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "play_sources" do
    field :title, :string
    field :author, :string
    field :editor, :string
    field :editor_role, :string
    field :note, :string
    field :publisher, :string
    field :pub_place, :string
    field :pub_date, :string
    field :language, :string
    field :position, :integer, default: 0
    field :origin, :string, default: "manual"

    belongs_to :play, Playcode.Catalogue.Play

    timestamps(type: :utc_datetime)
  end

  def changeset(source, attrs) do
    source
    |> cast(attrs, [
      :title,
      :author,
      :editor,
      :editor_role,
      :note,
      :publisher,
      :pub_place,
      :pub_date,
      :language,
      :position,
      :play_id,
      :origin
    ])
    |> validate_inclusion(:origin, Playcode.Catalogue.origins())
  end
end
