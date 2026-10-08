defmodule Playcode.PlayContent.Division do
  @moduledoc """
  A section of a play's text: an act holding scenes (`parent_id`), or a front-matter
  section such as the prologue, the dedication or the cast list (`elenco`).

  `type` is the TEI `@type` as the edition spells it: Spanish (`acto`, `jornada`,
  `escena`), English (`act`, `scene`) or French (`acte`). `PlaycodeWeb.PlayLabels` names
  it for display. `title` is the `<head>`. `position` orders a division among its siblings.

  `loaded_elements` is filled when the play's content is loaded as a tree, never
  stored.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "play_divisions" do
    field :type, :string
    field :number, :integer
    field :title, :string
    field :position, :integer, default: 0

    belongs_to :play, Playcode.Catalogue.Play
    belongs_to :parent, __MODULE__
    has_many :children, __MODULE__, foreign_key: :parent_id
    has_many :elements, Playcode.PlayContent.Element

    field :loaded_elements, {:array, :map}, virtual: true, default: []

    timestamps(type: :utc_datetime)
  end

  def changeset(division, attrs) do
    division
    |> cast(attrs, [:type, :number, :title, :position, :play_id, :parent_id])
    |> validate_required([:type])
    |> validate_inclusion(:type, ~w(
      acto escena prologo argumento dedicatoria elenco front jornada introduccion_editor
      act scene prologue epilogue induction
      acte scene prologue epilogue
      play circunstancia_accion introduccion_editor_digital nota_edicion_digital head_title
      interlude dumb_show auto
    ))
  end
end
