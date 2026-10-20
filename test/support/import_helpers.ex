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
  alias Playcode.Import.TeiImport

  @doc """
  A TEI document. Every option is a raw XML fragment dropped into place, except
  `:title` and `:code`.

  Options: `:title`, `:code`, `:title_stmt`, `:file_desc` (between titleStmt and
  publicationStmt: editionStmt, extent), `:publication_stmt`, `:source_desc`,
  `:encoding_desc`, `:profile_desc`, `:revision_desc` (the changes inside `revisionDesc`), `:front`, `:body`,
  `:back`.
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
        #{if opts[:encoding_desc], do: "<encodingDesc>#{opts[:encoding_desc]}</encodingDesc>"}
        #{if opts[:profile_desc], do: "<profileDesc>#{opts[:profile_desc]}</profileDesc>"}
        #{if opts[:revision_desc], do: "<revisionDesc>#{opts[:revision_desc]}</revisionDesc>"}
      </teiHeader>
      <text>
        <front>#{opts[:front]}</front>
        <body>#{opts[:body]}</body>
        #{if opts[:back], do: "<back>#{opts[:back]}</back>"}
      </text>
    </TEI>
    """
  end

  # The importer strips hyphens from a code, so TestFixtures.unique_code/0 ("PLAY-1")
  # would be stored as something else.
  defp tei_code, do: "T#{System.unique_integer([:positive])}"

  @doc """
  `test/fixtures/outline.xml`, a play with a cast list, a paratext and the scene of the
  action in every place one can stand, under a code of its own: async tests importing one
  code would wait on each other's unique index.
  """
  def outline_xml do
    "test/fixtures/outline.xml" |> File.read!() |> String.replace("EMOTHE9990", tei_code())
  end

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
    {:ok, play} = xml |> write_tmp!() |> TeiImport.import_file()
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

  @doc """
  The order of a file's text: each child of `<front>`, `<body>` and `<back>` as
  `"front/div[elenco]"` or `"front/set"`, the type in brackets when it has one, and after
  each div1 its castList and div2 children, `"body/div1[acto]/castList"`.
  """
  def text_order(xml) do
    [text] = xml |> parse() |> descendants("text")

    for section <- ~w(front body back),
        {_, _, children} <- children_named(text, section),
        {name, _, inner} = child <- children,
        own = "#{section}/#{order_label(child)}",
        label <- [own | if(name == "div1", do: nested_order(own, inner), else: [])],
        do: label
  end

  defp nested_order(own, children),
    do:
      for(
        {name, _, _} = child <- children,
        name in ~w(castList div2),
        do: "#{own}/#{order_label(child)}"
      )

  defp order_label({name, attrs, _}) do
    case List.keyfind(attrs, "type", 0) do
      {_, type} -> "#{name}[#{type}]"
      nil -> name
    end
  end

  @doc "Whether each of `strings` appears in `text`, each after the one before it."
  def in_order?(text, strings) do
    Enum.reduce_while(strings, 0, fn string, from ->
      case :binary.match(text, string, scope: {from, byte_size(text) - from}) do
        {at, length} -> {:cont, at + length}
        :nomatch -> {:halt, false}
      end
    end) != false
  end

  @doc "How many times `string` appears in `text`."
  def occurrences(text, string), do: length(:binary.matches(text, string))

  @doc """
  The headings of `test/fixtures/outline.xml` in its outline's order, as a page prints
  them: the front matter, the acts with their lists and scenes, the items between and
  after them; and the direction act 1 opens with, after the list that opens it.
  """
  def outline_headings do
    ["DEDICATORIA", "LUGAR DE LA ACCIÓN", "PERSONAS", "COMEDIA DE LOS ELENCOS", "ACTO PRIMERO"] ++
      ["Personas del acto primero", "Suenan cajas.", "ESCENA I", "Sale de nuevo", "ESCENA II"] ++
      ["Personas del acto segundo", "LOA", "ACTO SEGUNDO", "EPÍLOGO", "Personas que no hablan"]
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

  @doc """
  The text of every `tag` element in the body, outside notes, as a reader reads it: its
  notes left out, its pieces joined as written (`Iliria<note/>.` reads "Iliria."),
  whitespace collapsed.
  """
  def reading_texts(xml, tag) do
    xml
    |> parse()
    |> descendants("body")
    |> Enum.flat_map(&outside_notes(&1, tag))
    |> Enum.map(fn element ->
      element
      |> tokens()
      |> Enum.filter(&is_binary/1)
      |> Enum.join()
      |> String.replace(~r/\s+/u, " ")
      |> String.trim()
    end)
  end

  @doc """
  Each `tag` element of the body, in document order, as `{attributes, text}`: its text
  with each `<lb/>` written " | " and each `<lb n="…"/>` " [n] ", its notes left out,
  whitespace collapsed. `in_notes: true` reads the `tag` elements inside the body's notes
  instead.
  """
  def xml_lines(xml, tag, opts \\ []) do
    body = xml |> parse() |> descendants("body") |> List.first()

    elements =
      if opts[:in_notes],
        do: body |> descendants("note") |> Enum.flat_map(&descendants(&1, tag)),
        else: outside_notes(body, tag)

    Enum.map(elements, fn {_name, attrs, children} ->
      text =
        children |> Enum.map_join(&lined/1) |> String.replace(~r/\s+/u, " ") |> String.trim()

      {Map.new(attrs), text}
    end)
  end

  defp lined({"lb", attrs, _}) do
    case Map.new(attrs)["n"] do
      nil -> " | "
      n -> " [#{n}] "
    end
  end

  defp lined({"note", _, _}), do: ""
  defp lined({"app", _, _}), do: ""
  defp lined({_name, _attrs, children}), do: Enum.map_join(children, &lined/1)
  defp lined(text) when is_binary(text), do: text

  @doc """
  Every `<note>` in the body, in document order, as a map: `in`, the tag of the line,
  paragraph, stage direction, speaker or heading it sits in; `after`, that element's text
  before it (notes left out, whitespace collapsed); its `n`, `type` and `term`; the text
  of each `<p>`; and `text`, all of its text.
  """
  def xml_notes(xml) do
    xml
    |> parse()
    |> descendants("body")
    |> Enum.flat_map(&leaf_notes/1)
  end

  @leaves ~w(l p stage speaker head trailer)

  defp leaf_notes({name, _, _} = leaf) when name in @leaves do
    {notes, _before} =
      leaf
      |> tokens()
      |> Enum.flat_map_reduce("", fn
        {:note, note}, before -> {[note_map(note, name, before)], before}
        {:app, _app}, before -> {[], before}
        text, before -> {[], before <> text}
      end)

    notes
  end

  defp leaf_notes({_name, _, children}), do: Enum.flat_map(children, &leaf_notes/1)
  defp leaf_notes(_text), do: []

  # An element's text, notes and entries in order: text as binaries, each note as
  # {:note, element}, each entry of the critical apparatus as {:app, element}.
  defp tokens({_name, _, children}) do
    Enum.flat_map(children, fn
      {"note", _, _} = note -> [{:note, note}]
      {"app", _, _} = app -> [{:app, app}]
      {_, _, _} = element -> tokens(element)
      text -> [text]
    end)
  end

  defp note_map({"note", attrs, _children} = note, tag, before) do
    attrs = Map.new(attrs)

    %{
      in: tag,
      after: before |> String.replace(~r/\s+/u, " ") |> String.trim(),
      n: attrs["n"],
      type: attrs["type"],
      term:
        case children_named(note, "term") do
          [term | _] -> text(term)
          [] -> nil
        end,
      paragraphs: note |> children_named("p") |> Enum.map(&text/1),
      text: text(note)
    }
  end

  @doc """
  Every `<app>` of the critical apparatus in the body, outside notes, in document order,
  as a map: `in`, the tag of the line, paragraph, stage direction, speaker or heading it
  sits in; `after`, that element's text before it (notes and entries left out, whitespace
  collapsed); its `n`, `type` and `to`; `readings`, each `{tag, wit, text, note}`, the text
  without the reading's note; and `note`, the text of its own note, or nil.
  """
  def xml_apps(xml) do
    xml
    |> parse()
    |> descendants("body")
    |> Enum.flat_map(&leaf_apps/1)
  end

  defp leaf_apps({name, _, _} = leaf) when name in @leaves do
    {apps, _before} =
      leaf
      |> tokens()
      |> Enum.flat_map_reduce("", fn
        {:app, app}, before -> {[app_map(app, name, before)], before}
        {:note, _note}, before -> {[], before}
        text, before -> {[], before <> text}
      end)

    apps
  end

  defp leaf_apps({_name, _, children}), do: Enum.flat_map(children, &leaf_apps/1)
  defp leaf_apps(_text), do: []

  defp app_map({"app", attrs, children} = app, tag, before) do
    attrs = Map.new(attrs)

    %{
      in: tag,
      after: squash(before),
      n: attrs["n"],
      type: attrs["type"],
      to: attrs["to"],
      readings:
        for {name, reading_attrs, reading_children} <- children, name in ~w(lem rdg) do
          {notes, words} = Enum.split_with(reading_children, &match?({"note", _, _}, &1))

          {name, Map.new(reading_attrs)["wit"], flat_text({name, [], words}),
           Enum.map(notes, &flat_text/1) |> List.first()}
        end,
      note:
        case children_named(app, "note") do
          [note] -> flat_text(note)
          [] -> nil
        end
    }
  end

  # All of an element's text, joined as written, whitespace collapsed.
  defp flat_text({_name, _attrs, children}),
    do: children |> Enum.map_join(&flat_text/1) |> squash()

  defp flat_text(text) when is_binary(text), do: text

  defp squash(text), do: text |> String.replace(~r/\s+/u, " ") |> String.trim()

  defp outside_notes({"note", _, _}, _tag), do: []

  defp outside_notes({name, _, children} = element, tag) do
    own = if name == tag, do: [element], else: []
    own ++ Enum.flat_map(children, &outside_notes(&1, tag))
  end

  defp outside_notes(_text, _tag), do: []

  @doc """
  Every `<stage>` that is a direct child of an `<l>` or `<p>` in the body, in document
  order, as a map: `in`, that line's tag; `type`; `text`; and `before` and `after`, the
  rest of the line's text on either side of it, whitespace collapsed.
  """
  def xml_inline_stages(xml) do
    xml
    |> parse()
    |> descendants("body")
    |> Enum.flat_map(&inline_stages/1)
  end

  defp inline_stages({name, _, children}) when name in ~w(l p) do
    children
    |> Enum.with_index()
    |> Enum.flat_map(fn
      {{"stage", attrs, _} = stage, i} ->
        {before, [_stage | rest]} = Enum.split(children, i)

        [
          %{
            in: name,
            type: Map.new(attrs)["type"],
            text: text(stage),
            before: text({name, [], before}),
            after: text({name, [], rest})
          }
        ]

      _other ->
        []
    end)
  end

  defp inline_stages({_name, _, children}), do: Enum.flat_map(children, &inline_stages/1)
  defp inline_stages(_text), do: []

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
