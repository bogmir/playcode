defmodule Playcode.PlayContent.Note.Reading do
  @moduledoc """
  One reading of a variant (`Note.variant?/1`): a TEI `<lem>` (`lemma`, the reading the
  edition follows) or `<rdg>`. `wit` is the witnesses' sigla as the file writes them
  (`"#1623b #1626a"`), `text` the reading with `<<…>>` italics, `note` the reading's own
  note. `sigla` is filled by `PlayContent.load_play_content/2`: each siglum with what
  `Witnesses.short_names/1` says it names, or nil; it is never stored.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Playcode.Text

  @primary_key false
  embedded_schema do
    field :lemma, :boolean, default: false
    field :wit, :string
    field :text, :string
    field :note, :string
    field :sigla, {:array, :any}, virtual: true, default: []
  end

  def changeset(reading, attrs) do
    reading
    |> cast(attrs, [:lemma, :wit, :text, :note])
    |> update_change(:wit, &Text.squeeze/1)
    |> update_change(:text, &Text.squeeze/1)
  end

  @doc ~S|The sigla `wit` names, without their `#`: `"#P3 #MP"` is `["P3", "MP"]`; `"#"` names none.|
  def sigla(nil), do: []

  def sigla(wit),
    do:
      wit |> String.split() |> Enum.map(&String.trim_leading(&1, "#")) |> Enum.reject(&(&1 == ""))
end
