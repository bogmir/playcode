defmodule Playcode.Bibliography.Entry do
  @moduledoc """
  One work cited, shared by every play that cites it, so one correction reaches them all.

  Two levels, as in TEI's `biblStruct` and FileMaker's own record: `analytic_*` is the
  article, chapter or section; `monogr_*` the book or journal it is in. A book alone fills
  only `monogr_*`. `note` is for researchers only (the project's answer, 2026-10-07);
  `public_note` is printed with the citation.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Playcode.PlayContent.InlineMarkup

  @primary_key {:id, :binary_id, autogenerate: true}

  # Also the order a play's bibliography is shown in.
  @kinds ~w(modern_edition criticism translation adaptation)

  @pub_types ~w(article book_section scholarly_edition book proceedings prologue festschrift
                electronic thesis collection)

  @languages ~w(es en fr it pt de)

  # An entry names something when one of these is filled.
  @names [
    :analytic_author,
    :analytic_title,
    :analytic_editors,
    :monogr_author,
    :monogr_title,
    :monogr_editors
  ]

  @fields [
    :kind,
    :pub_type,
    :language,
    :analytic_author,
    :analytic_title,
    :analytic_editors,
    :analytic_translators,
    :monogr_author,
    :monogr_title,
    :monogr_editors,
    :monogr_translators,
    :original_title,
    :edition,
    :volume,
    :volumes_total,
    :issue,
    :pages,
    :pub_place,
    :publisher,
    :year_text,
    :url,
    :url_accessed_on,
    :series,
    :siglum,
    :public_note,
    :note
  ]

  # How a TEI file names them: each kind is a `listBibl/@type`, each type a
  # `biblStruct/@type`, FileMaker's own type names (T12.11) in Spanish, as the corpus spells
  # its other types.
  @tei_lists %{
    "modern_edition" => "ediciones_modernas",
    "criticism" => "critica",
    "translation" => "traducciones",
    "adaptation" => "adaptaciones"
  }

  @tei_types %{
    "article" => "articulo_revista",
    "book_section" => "seccion_libro",
    "scholarly_edition" => "edicion_estudioso",
    "book" => "libro",
    "proceedings" => "acta",
    "prologue" => "prologo",
    "festschrift" => "homenaje",
    "electronic" => "publicacion_electronica",
    "thesis" => "tesis_doctorado",
    "collection" => "coleccion"
  }

  @described @fields -- [:note]

  # The fields that hold people, several in one field as FileMaker keeps them.
  @people [
    :analytic_author,
    :monogr_author,
    :analytic_editors,
    :monogr_editors,
    :analytic_translators,
    :monogr_translators
  ]

  # The fields the export writes through InlineMarkup, as italics.
  @inline [
    :analytic_author,
    :analytic_title,
    :monogr_author,
    :monogr_title,
    :original_title,
    :series,
    :public_note
  ]

  def kinds, do: @kinds
  def pub_types, do: @pub_types
  def languages, do: @languages

  @doc """
  The people of a field, one each: FileMaker separates them with ";", written "; ", " ; "
  or ";". A TEI file gives each an element, and a description joins them with "; ".
  """
  def people(field), do: String.split(field, ~r/\s*;\s*/, trim: true)

  @doc "The `listBibl/@type` of a kind's references in a TEI file."
  def tei_list(kind), do: @tei_lists[kind]

  @doc "The kind a `listBibl/@type` names; nil for one not here."
  def kind_from_tei_list(type),
    do: Enum.find_value(@tei_lists, &(elem(&1, 1) == type && elem(&1, 0)))

  @doc "The `biblStruct/@type` of a publication type in a TEI file; nil for none."
  def tei_type(pub_type), do: @tei_types[pub_type]

  @doc "The publication type a `biblStruct/@type` names; nil for one not here."
  def pub_type_from_tei(type),
    do: Enum.find_value(@tei_types, &(elem(&1, 1) == type && elem(&1, 0)))

  @doc """
  The URL a TEI file gives, as a `ptr`: the address trimmed, or nil when it is not an
  http(s) address. ponytail: FileMaker's strays (". http://…") stay in the database for
  curators to clean.
  """
  def tei_url(nil), do: nil

  def tei_url(url) do
    url = String.trim(url)
    if url =~ ~r{\Ahttps?://\S+\z}i, do: url
  end

  schema "bibliography_entries" do
    field :kind, :string
    field :pub_type, :string
    field :language, :string
    field :analytic_author, :string
    field :analytic_title, :string
    field :analytic_editors, :string
    field :analytic_translators, :string
    field :monogr_author, :string
    field :monogr_title, :string
    field :monogr_editors, :string
    field :monogr_translators, :string
    field :original_title, :string
    field :edition, :string
    field :volume, :string
    field :volumes_total, :string
    field :issue, :string
    field :pages, :string
    field :pub_place, :string
    field :publisher, :string
    field :year_text, :string
    field :url, :string
    field :url_accessed_on, :string
    field :series, :string
    field :siglum, :string
    field :public_note, :string
    field :note, :string
    field :filemaker_id, :string

    has_many :links, Playcode.Bibliography.Link

    timestamps(type: :utc_datetime)
  end

  @doc "What a form may set. `filemaker_id` is set only by the import, on the struct."
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, @fields)
    |> validate_required([:kind])
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:pub_type, @pub_types)
    |> validate_inclusion(:language, @languages)
    |> validate_named()
    |> unique_constraint(:filemaker_id)
  end

  @doc "Whether `entry` (an entry or a map with atom keys) has an author, an editor or a title."
  def named?(entry), do: Enum.any?(@names, &(entry |> Map.get(&1) |> present?()))

  defp validate_named(changeset) do
    if changeset |> apply_changes() |> named?(),
      do: changeset,
      else: add_error(changeset, :monogr_title, "needs an author, an editor or a title")
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  @doc """
  The reference as a TEI file carries it: every public field, whitespace collapsed, blank
  as nil, the URL only as `tei_url/1` gives it, the italics as the export writes them
  (`as_written/1`), and the people of a field joined with "; " (`people/1`). It is all a file says of a reference, so it is what a file's reference
  is matched on; researchers' `note` never leaves Playcode and is not in it.
  """
  def description(%__MODULE__{} = entry) do
    @described
    |> Map.new(fn field ->
      value = Map.fetch!(entry, field)
      value = if field in @inline, do: as_written(value), else: value
      value = if field in @people and value, do: value |> people() |> Enum.join("; "), else: value
      {field, collapse(value)}
    end)
    |> Map.update!(:url, &tei_url/1)
  end

  # A field's italics as the export writes them and the parser reads them back: the
  # pieces InlineMarkup makes of it, an empty <<>> gone, touching italic runs as one.
  defp as_written(nil), do: nil

  defp as_written(text) do
    text
    |> InlineMarkup.parts()
    |> Enum.chunk_by(& &1.italic)
    |> Enum.map_join(fn
      [%{italic: true} | _] = run -> "<<" <> Enum.map_join(run, & &1.text) <> ">>"
      run -> Enum.map_join(run, & &1.text)
    end)
  end

  defp collapse(nil), do: nil

  defp collapse(text) do
    case text |> String.replace(~r/\s+/u, " ") |> String.trim() do
      "" -> nil
      text -> text
    end
  end
end
