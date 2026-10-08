defmodule Playcode.ImportHelpers do
  @moduledoc """
  Drive the importers through their public entry points and read the result back
  the way the outside world sees it: as exported TEI.

      xml = roundtrip(tei(body: ~s(<div1 type="acto" n="1"><head>I</head></div1>)))
      assert [{%{"type" => "acto"}, "I"}] = xml_elements(xml, "div1")

  Assert on what a TEI consumer reads, never on how rows are stored.
  """

  import ExUnit.Callbacks, only: [on_exit: 1]

  alias Playcode.Catalogue
  alias Playcode.Export.TeiXml
  alias Playcode.Import.TeiParser

  @doc """
  A TEI document. Every option is a raw XML fragment dropped into place, except
  `:title` and `:code`.

  Options: `:title`, `:code`, `:title_stmt`, `:file_desc` (between titleStmt and
  publicationStmt: editionStmt, extent), `:publication_stmt`, `:source_desc`,
  `:profile_desc`, `:front`, `:body`.
  """
  def tei(opts \\ []) do
    code = Keyword.get_lazy(opts, :code, &tei_code/0)

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <TEI xmlns="http://www.tei-c.org/ns/1.0">
      <teiHeader>
        <fileDesc>
          <titleStmt>
            <title>#{Keyword.get(opts, :title, "Test Play")}</title>
            #{opts[:title_stmt]}
          </titleStmt>
          #{opts[:file_desc]}
          <publicationStmt>
            <idno>#{code}</idno>
            #{opts[:publication_stmt]}
          </publicationStmt>
          #{if opts[:source_desc], do: "<sourceDesc>#{opts[:source_desc]}</sourceDesc>"}
        </fileDesc>
        #{if opts[:profile_desc], do: "<profileDesc>#{opts[:profile_desc]}</profileDesc>"}
      </teiHeader>
      <text>
        <front>#{opts[:front]}</front>
        <body>#{opts[:body]}</body>
      </text>
    </TEI>
    """
  end

  # The importer strips hyphens from a code, so TestFixtures.unique_code/0 ("PLAY-1")
  # would be stored as something else.
  defp tei_code, do: "T#{System.unique_integer([:positive])}"

  @doc "Writes `contents` to a temp file removed when the test exits."
  def write_tmp!(contents, ext \\ ".xml") do
    path = Path.join(System.tmp_dir!(), "import-#{System.unique_integer([:positive])}#{ext}")
    File.write!(path, contents)
    on_exit(fn -> File.rm(path) end)
    path
  end

  @doc """
  A minimal .docx whose body is one Word paragraph per string, as the
  "premarcado" Word importer reads it. Returns the temp file's path.
  """
  def docx(paragraphs) do
    body =
      Enum.map_join(paragraphs, "\n", fn text ->
        escaped =
          text
          |> String.replace("&", "&amp;")
          |> String.replace("<", "&lt;")
          |> String.replace(">", "&gt;")

        ~s(<w:p><w:r><w:t xml:space="preserve">#{escaped}</w:t></w:r></w:p>)
      end)

    document = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
      <w:body>#{body}</w:body>
    </w:document>
    """

    {:ok, {_name, zip}} =
      :zip.create(~c"play.docx", [{~c"word/document.xml", document}], [:memory])

    write_tmp!(zip, ".docx")
  end

  @doc "Imports `xml` and returns the play as stored, with its associations."
  def import_tei!(xml) do
    {:ok, play} = xml |> write_tmp!() |> TeiParser.import_file()
    Catalogue.get_play_with_all!(play.id)
  end

  @doc """
  An original and its translation that number and name their divisions differently, as
  real editions do: `acto`/`escena` with `n` against `act`/`scene`, a scene with no `n`,
  and a prologue numbered like the first act. Both complete, so a visitor can compare
  them. Returns `%{original: play, translation: play}`.
  """
  def differently_numbered_editions do
    original =
      import_tei!(
        tei(
          body: """
          <div1 type="acto" n="0"><head>PRÓLOGO</head>
            <sp><speaker>PRÓLOGO</speaker><l n="1">uno</l></sp>
          </div1>
          <div1 type="acto" n="1"><head>ACTO I</head>
            <div2 type="escena" n="1"><head>ESCENA I</head>
              <sp><speaker>ANA</speaker><l n="2">dos</l></sp>
              <sp><speaker>BLAS</speaker><l n="3">tres</l></sp>
            </div2>
          </div1>
          """
        )
      )

    translation =
      import_tei!(
        tei(
          body: """
          <div1 type="act" n="1"><head>PROLOGUE</head>
            <sp><speaker>PROLOGUE</speaker><l n="1">one</l></sp>
          </div1>
          <div1 type="act" n="1"><head>ACT I</head>
            <div2 type="scene"><head>SCENE I</head>
              <sp><speaker>ANNE</speaker><l n="2">two</l></sp>
              <sp><speaker>BLAISE</speaker><l n="3">three</l></sp>
            </div2>
          </div1>
          """
        )
      )

    {:ok, original} = Catalogue.update_play(original, %{is_complete: true})

    {:ok, translation} =
      Catalogue.update_play(translation, %{
        is_complete: true,
        parent_play_id: original.id,
        relationship_type: "traduccion"
      })

    %{original: original, translation: translation}
  end

  @doc "The TEI the platform exports for a play."
  def export_tei(play), do: TeiXml.generate(Catalogue.get_play_with_all!(play.id))

  @doc "Imports `xml`, then exports the play it became."
  def roundtrip(xml), do: xml |> import_tei!() |> export_tei()

  @doc """
  Every `tag` element in document order, as `{attributes, text}`. Text is all the
  descendant text, whitespace-collapsed. `within: "sourceDesc"` keeps only
  elements with that ancestor.
  """
  def xml_elements(xml, tag, opts \\ []) do
    xml = Regex.replace(~r/^\s*<\?xml[^?]*\?>/, xml, "")
    {:ok, root} = Saxy.SimpleForm.parse_string(xml)
    within = opts[:within]

    root
    |> collect(tag, [])
    |> Enum.filter(fn {_attrs, _text, ancestors} -> is_nil(within) or within in ancestors end)
    |> Enum.map(fn {attrs, text, _ancestors} -> {attrs, text} end)
  end

  @doc """
  The body's shape: one `{div1 attributes, head, [{div2 attributes, head}]}` per
  top-level division. A division with no head has `nil`.
  """
  def outline(xml) do
    xml
    |> parse()
    |> descendants("body")
    |> List.first()
    |> children_named("div1")
    |> Enum.map(fn div1 ->
      scenes = div1 |> children_named("div2") |> Enum.map(&{attrs(&1), head(&1)})
      {attrs(div1), head(div1), scenes}
    end)
  end

  defp parse(xml) do
    {:ok, root} =
      xml |> String.replace(~r/^\s*<\?xml[^?]*\?>/, "") |> Saxy.SimpleForm.parse_string()

    root
  end

  defp descendants({name, _, children} = el, tag) do
    own = if name == tag, do: [el], else: []
    own ++ Enum.flat_map(children, &descendants(&1, tag))
  end

  defp descendants(_text, _tag), do: []

  defp children_named({_, _, children}, tag), do: Enum.filter(children, &match?({^tag, _, _}, &1))
  defp attrs({_, attrs, _}), do: Map.new(attrs)

  defp head(el) do
    case children_named(el, "head") do
      [h | _] -> text(h)
      [] -> nil
    end
  end

  @doc "The text of every `tag` element, in document order."
  def xml_texts(xml, tag, opts \\ []),
    do: xml |> xml_elements(tag, opts) |> Enum.map(&elem(&1, 1))

  defp collect({name, attrs, children}, tag, ancestors) do
    inner = Enum.flat_map(children, &collect(&1, tag, [name | ancestors]))

    if name == tag,
      do: [{Map.new(attrs), text({name, attrs, children}), ancestors} | inner],
      else: inner
  end

  defp collect(_text, _tag, _ancestors), do: []

  defp text({_name, _attrs, children}) do
    children
    |> Enum.map_join(" ", fn
      binary when is_binary(binary) -> binary
      element -> text(element)
    end)
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end
end
