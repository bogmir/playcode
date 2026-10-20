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
    has_many :notes, Playcode.PlayContent.Note, preload_order: [asc: :offset, asc: :position]

    has_many :entries, Playcode.PlayContent.CastListEntry,
      foreign_key: :cast_list_id,
      preload_order: [asc: :position, asc: :id]

    field :loaded_elements, {:array, :map}, virtual: true, default: []

    timestamps(type: :utc_datetime)
  end

  @doc """
  Keys pairing each of `siblings` with its counterpart in another edition, for the
  side-by-side comparison: its kind and its place among the siblings of that kind
  (`act-0`, `act-1`, `scene-0`). Editions spell and number divisions differently
  (`acto` against `act`, a scene with `n="1"` against one with none, a prologue numbered
  like the first act), so `type` and `number` do not pair them.
  """
  def sync_keys(siblings) do
    {keys, _seen} =
      Enum.map_reduce(siblings, %{}, fn division, seen ->
        kind = kind(division.type)
        place = Map.get(seen, kind, 0)
        {"#{kind}-#{place}", Map.put(seen, kind, place + 1)}
      end)

    keys
  end

  defp kind(type) when type in ~w(acto act acte jornada play), do: "act"
  defp kind(type) when type in ~w(escena scene), do: "scene"
  defp kind(type) when type in ~w(prologo prologue), do: "prologue"
  defp kind(type), do: type

  @body_types ~w(acto jornada prologo argumento act acte play prologue induction epilogue
                 interlude dumb_show auto poema)

  @doc """
  The types of a division of the text itself, as the files write them between the acts:
  acts, and the prologues, inductions, interludes and dumb shows around them; and the
  poem that is the whole text of the *Arte nuevo* and its translations (question 41).
  """
  def body_types, do: @body_types

  @doc """
  A division's scenes, its children but its cast lists, each with its number from 1: a cast
  list between two scenes shares their positions, not their numbering.
  """
  def numbered_scenes(division),
    do: division.children |> Enum.reject(&(&1.type == "elenco")) |> Enum.with_index(1)

  @doc """
  An act's `children` as its file writes them: the cast lists that open the act, which
  stand before its own elements (a bare `<castList>`), and the rest, after them. An empty
  list is written as a division of its own, so it never opens an act.
  """
  def split_opening_lists(children),
    do: Enum.split_while(children, &(&1.type == "elenco" and &1.entries != []))

  def changeset(division, attrs) do
    division
    |> cast(attrs, [:type, :number, :title, :position, :play_id, :parent_id])
    |> validate_required([:type])
    |> validate_inclusion(:type, ~w(
      acto escena prologo argumento dedicatoria elenco front jornada introduccion_editor
      act scene prologue epilogue induction
      acte scene prologue epilogue
      play circunstancia_accion introduccion_editor_digital nota_edicion_digital head_title
      interlude dumb_show auto poema
    ))
  end
end
