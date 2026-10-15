defmodule Playcode.Catalogue.Paratext do
  @moduledoc """
  A paratext (CONTEXT.md): a text that stands before the play's text, or after it
  (`back`), without being part of it: a heading, paragraphs, or both. Its `kind` says what it is and decides the concept:
  an editorial text, written for this edition (`editorial?/1`); the scene of the action
  (`lugar_accion`, TEI's `<set>`, printed with the cast list, `scene?/1`), which is not a
  paratext but is kept here; or a paratext printed with the play in its early edition.
  A file's kind outside `kinds/0` is kept as the file gives it, as a stage direction's
  is. `origin` works as for `PlayEditor`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @printed ~w(dedicatoria epistola introduccion_autor prologo argumento licencia
              noticia_representacion title_page head_title epilogo despedida colofon)
  @editorial ~w(nota_edicion_digital introduccion_editor_digital introduccion_editor
                introduccion_traductor apendice)
  @scene "lugar_accion"

  schema "play_paratexts" do
    field :kind, :string
    field :heading, :string
    field :content, :string
    field :back, :boolean, default: false
    field :position, :integer, default: 0
    field :origin, :string, default: "manual"

    belongs_to :play, Playcode.Catalogue.Play

    timestamps(type: :utc_datetime)
  end

  @doc "The kinds of paratext printed with the play in its early edition."
  def printed_kinds, do: @printed

  @doc "The kinds of editorial text, written for this edition (CONTEXT.md)."
  def editorial_kinds, do: @editorial

  @doc "The kinds Playcode names, in the admin's order; a file may give another word, which is kept."
  def kinds, do: @printed ++ @editorial ++ [@scene]

  @doc "Whether a kind is an editorial text."
  def editorial?(kind), do: kind in @editorial

  @doc "Whether a kind is the scene of the action, printed with the cast list."
  def scene?(kind), do: kind == @scene

  def changeset(paratext, attrs) do
    paratext
    |> cast(attrs, [:kind, :heading, :content, :back, :position, :play_id, :origin])
    |> update_change(:content, &paragraphs/1)
    |> validate_required([:kind])
    |> validate_heading_or_content()
    # One TEI token (teidata.enumerated), so whatever is stored exports schema-valid.
    |> validate_format(:kind, ~r/^[^\p{C}\p{Z}]+$/u)
    |> validate_inclusion(:origin, Playcode.Catalogue.origins())
    |> validate_scene_before_text()
  end

  # Line breaks and spaces as a TEI file gives them back (Text.squeeze/1), and any run of
  # blank lines one paragraph break, as the import reads `<lb/><lb/>`.
  defp paragraphs(content) do
    with text when is_binary(text) <- Playcode.Text.squeeze(content),
         do: String.replace(text, ~r/\n{3,}/, "\n\n")
  end

  # A paratext may be a heading alone: 12 head titles in the corpus are.
  defp validate_heading_or_content(changeset) do
    if get_field(changeset, :heading),
      do: changeset,
      else: validate_required(changeset, :content)
  end

  # The scene of the action is printed with the cast list and written as the front's <set>.
  defp validate_scene_before_text(changeset) do
    if scene?(get_field(changeset, :kind)) and get_field(changeset, :back),
      do: add_error(changeset, :back, "the scene of the action stands with the cast list"),
      else: changeset
  end
end
