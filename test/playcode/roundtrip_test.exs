defmodule Playcode.RoundtripTest do
  use Playcode.DataCase, async: true

  alias Playcode.ImportHelpers

  @moduledoc """
  Roundtrip tests using real-world TEI fixture files from the EMOTHE corpus.
  Verifies that import → export preserves structural integrity:
  verses, speeches, stage directions, characters, acts/scenes, etc.

  Fixtures: the tracked test/fixtures/*.xml, plus the git-ignored
  test/fixtures/tei_files/ when present (UTF-16 encoded TEI P5 XML).
  """

  @fields ~w(acts scenes characters speeches verses line_groups stage_dirs asides
             split_parts verse_type_attrs hidden_chars heads front_paratexts back_paratexts
             speaker_refs notes inline_stages line_breaks line_numbers paragraph_numbers
             trailers)a

  # The words the corpus closes with, as the importer reads them (`TeiParser`).
  @closing_words ~r/\A\W*(?:il\s+)?fin(?:e|is)?\b|\A\W*t\s*e\s*l\s*[óo]\s*n\b/iu

  # Read a possibly UTF-16 file and return UTF-8 string
  defp read_original(path) do
    raw = File.read!(path)

    case raw do
      <<0xFF, 0xFE, rest::binary>> ->
        :unicode.characters_to_binary(rest, {:utf16, :little})

      <<0xFE, 0xFF, rest::binary>> ->
        :unicode.characters_to_binary(rest, {:utf16, :big})

      <<first, 0x00, _rest::binary>> when first != 0x00 ->
        :unicode.characters_to_binary(raw, {:utf16, :little})

      <<0xEF, 0xBB, 0xBF, rest::binary>> ->
        rest

      _ ->
        raw
    end
  end

  # Extract <body>...</body> content (avoids counting <p> in teiHeader)
  defp extract_body(xml) do
    case Regex.run(~r/<body>(.*)<\/body>/s, xml) do
      [_, body] -> body
      _ -> xml
    end
  end

  # Extract <front>...</front> content
  defp extract_front(xml) do
    case Regex.run(~r/<front>(.*)<\/front>/s, xml) do
      [_, front] -> front
      _ -> ""
    end
  end

  defp extract_back(xml) do
    case Regex.run(~r/<back>(.*)<\/back>/s, xml) do
      [_, back] -> back
      _ -> ""
    end
  end

  defp count_tag(xml, tag), do: Regex.scan(~r/<#{tag}[\s>\/]/, xml) |> length()

  # Count stage directions that the parser actually imports:
  # only <stage> elements that are direct children of div2, sp, or lg
  # (not delivery stages, not inline within <l> or <p>)
  defp count_stage_dirs(body) do
    clean = Regex.replace(~r/<\?xml[^?]*\?>/, body, "")
    {:ok, tree} = Saxy.SimpleForm.parse_string("<root>#{clean}</root>")
    count_stage_children(tree)
  end

  defp count_stage_children({_name, _attrs, children}) do
    Enum.reduce(children, 0, fn
      {"stage", attrs, _}, acc ->
        if delivery?(attrs), do: acc, else: acc + 1

      {tag, _, _} = el, acc when tag in ~w(root div1 div2 sp lg) ->
        acc + count_stage_children(el)

      # Don't recurse into l, p, note, etc. — their stages are inline
      _, acc ->
        acc
    end)
  end

  defp attr_val(attrs, key), do: Enum.find_value(attrs, fn {k, v} -> if k == key, do: v end)

  # As the importer reads it: 24 source files spell TEI's "delivery" "delivery_".
  defp delivery?(attrs), do: attr_val(attrs, "type") in ["delivery", "delivery_"]

  # Count <l> elements with a part attribute (split verses)
  defp count_part_attrs(body) do
    Regex.scan(~r/<l\s[^>]*part="[IMF]"/, body) |> length()
  end

  # Count <sp> elements whose who attribute names at least one character in the cast
  # list. A reference to an id the file never defines (EMOTHE0732's who="#L’OMBRE",
  # whose castItem is xml:id="OMBRE") points at nobody and is rightly not exported.
  defp count_who_attrs(body, front) do
    cast_ids =
      Regex.scan(~r/<role\b[^>]*xml:id="([^"]+)"/, front, capture: :all_but_first)
      |> List.flatten()
      # Ids like xml:id="WASP\n" (EMOTHE0346) are trimmed on import, so trim here too.
      |> MapSet.new(&String.trim/1)

    Regex.scan(~r/<sp\s[^>]*who="([^"]*)"/, body, capture: :all_but_first)
    |> Enum.count(fn [who] ->
      who |> String.split() |> Enum.any?(&MapSet.member?(cast_ids, String.trim_leading(&1, "#")))
    end)
  end

  # Count <lg> elements with a non-empty type attribute (verse type annotations);
  # AL0644's lone type="" says nothing and is rightly not exported.
  defp count_verse_type_attrs(body) do
    Regex.scan(~r/<lg\s[^>]*type="[^"]/, body) |> length()
  end

  # Count <castItem> elements with ana="oculto" (hidden characters)
  defp count_hidden_chars(front) do
    Regex.scan(~r/<castItem\s[^>]*ana="oculto"/, front) |> length()
  end

  # Count the <div>s the parser imports as paratexts, in the front or the back: any but a
  # cast list ("elenco") or the bibliography, with a heading or a <p> holding text of its
  # own, and no verse (two files' sonnet waits on question 30). A <set> with paragraphs
  # counts too: 45 files give the scene of the action as a circunstancia_accion div, which
  # the export writes back as <set>, so the same paratext is a div on one side and a set
  # on the other.
  defp count_paratext_divs(xml) do
    clean = Regex.replace(~r/<\?xml[^?]*\?>/, xml, "")

    case Saxy.SimpleForm.parse_string("<root>#{clean}</root>") do
      {:ok, {_root, _attrs, children}} -> Enum.count(children, &paratext_div?/1)
      _ -> 0
    end
  end

  defp paratext_div?({tag, attrs, children}) when tag in ~w(div set) do
    attr_val(attrs, "type") not in ~w(elenco bibliografia) and
      not Enum.any?(children, &match?({"lg", _, _}, &1)) and
      Enum.any?(children, fn
        {name, _, inner} when name in ~w(head p) -> own_text(inner) != ""
        _ -> false
      end)
  end

  defp paratext_div?(_other), do: false

  defp own_text(children),
    do: Enum.map_join(children, fn t -> if is_binary(t), do: String.trim(t), else: "" end)

  # Count <head> elements inside div1/div2 (division titles in body)
  defp count_heads_in_body(body) do
    clean = Regex.replace(~r/<\?xml[^?]*\?>/, body, "")
    {:ok, tree} = Saxy.SimpleForm.parse_string("<root>#{clean}</root>")
    count_head_children(tree)
  end

  # An act's last scene holding only a heading of closing words ("FIN DE CORIOLANO."):
  # the importer reads it as the act's trailer (2026-10-21), so the export has a trailer
  # where the file has a scene and its heading.
  defp closing_scenes_as_trailers(counts, xml) do
    clean = Regex.replace(~r/<\?xml[^?]*\?>/, extract_body(xml), "")
    {:ok, tree} = Saxy.SimpleForm.parse_string("<root>#{clean}</root>")
    closing = count_closing_scenes(tree)

    %{
      counts
      | scenes: counts.scenes - closing,
        heads: counts.heads - closing,
        trailers: counts.trailers + closing
    }
  end

  defp count_closing_scenes({"div1", _attrs, children}) do
    with {"div2", _, scene} <- children |> Enum.reject(&is_binary/1) |> List.last(),
         [{"head", _, _} = head] <- Enum.reject(scene, &is_binary/1),
         true <- text_of(head) =~ @closing_words do
      1
    else
      _ -> 0
    end
  end

  defp count_closing_scenes({_name, _attrs, children}),
    do: children |> Enum.filter(&is_tuple/1) |> Enum.map(&count_closing_scenes/1) |> Enum.sum()

  defp count_head_children({_name, _attrs, children}) do
    Enum.reduce(children, 0, fn
      # An empty <head></head> (EMOTHE0075, 0341, 0733) carries nothing, and the
      # export rightly omits it.
      {"head", _, _} = head, acc ->
        if text_of(head) == "", do: acc, else: acc + 1

      {tag, _, _} = el, acc when tag in ~w(root div1 div2) ->
        acc + count_head_children(el)

      _, acc ->
        acc
    end)
  end

  defp structural_counts(xml) do
    body = extract_body(xml)
    front = extract_front(xml)

    %{
      verses: count_tag(body, "l"),
      speeches: count_tag(body, "sp"),
      stage_dirs: count_stage_dirs(body),
      line_groups: count_tag(body, "lg"),
      acts: count_tag(xml, "div1"),
      scenes: count_tag(xml, "div2"),
      characters: count_tag(front, "castItem"),
      asides: count_aside_elements(body),
      split_parts: count_part_attrs(body),
      speaker_refs: count_who_attrs(body, front),
      verse_type_attrs: count_verse_type_attrs(body),
      hidden_chars: count_hidden_chars(front),
      heads: count_heads_in_body(body),
      trailers: count_tag(body, "trailer"),
      front_paratexts: count_paratext_divs(front),
      back_paratexts: count_paratext_divs(extract_back(xml)),
      notes: count_notes(xml),
      inline_stages: count_inline_stages(body),
      line_breaks: count_line_breaks(body, :bare),
      line_numbers: count_line_breaks(body, :numbered),
      paragraph_numbers: length(Regex.scan(~r/<p\b[^>]*\sn="/, body))
    }
  end

  # Count <l> and <p> elements that contain at least one <seg type="aside">
  # (matches what the importer stores: one element per <l>/<p> with is_aside=true)
  defp count_aside_elements(body) do
    clean = Regex.replace(~r/<\?xml[^?]*\?>/, body, "")
    {:ok, tree} = Saxy.SimpleForm.parse_string("<root>#{clean}</root>")
    count_aside_leaves(tree)
  end

  defp count_aside_leaves({_name, _attrs, children}) do
    Enum.reduce(children, 0, fn
      {tag, _attrs, inner}, acc when tag in ~w(l p) ->
        has_aside =
          Enum.any?(inner, fn
            {"seg", seg_attrs, _} -> attr_val(seg_attrs, "type") == "aside"
            _ -> false
          end)

        if has_aside, do: acc + 1, else: acc

      {_tag, _, _} = child, acc ->
        acc + count_aside_leaves(child)

      _, acc ->
        acc
    end)
  end

  # <stage> children of <l> and <p> that the importer keeps, as markers in the line's
  # text: all but those of a line or paragraph all aside (kept_children/2).
  defp count_inline_stages(body) do
    clean = Regex.replace(~r/<\?xml[^?]*\?>/, body, "")
    {:ok, tree} = Saxy.SimpleForm.parse_string("<root>#{clean}</root>")
    count_inline_stage_leaves(tree)
  end

  # The <lb>s the importer keeps: all but those of a line all aside by its delivery
  # <stage> alone (kept_children/2), and one that ends a paragraph, which shows nothing and Note.paragraphs/1 trims (10 in the
  # notes of EMOTHE0254, 0730 and 0752; no paragraph of the play text ends with one).
  defp count_line_breaks(body, kind) do
    clean =
      body
      |> String.replace(~r/<\?xml[^?]*\?>/, "")
      |> String.replace(~r/<lb\b[^>]*\/>(\s*<\/p>)/, "\\1")

    {:ok, tree} = Saxy.SimpleForm.parse_string("<root>#{clean}</root>")
    count_breaks(tree, kind)
  end

  defp count_breaks({"lb", attrs, _}, kind),
    do: if(attr_val(attrs, "n") == nil == (kind == :bare), do: 1, else: 0)

  defp count_breaks({tag, _attrs, inner}, kind) when tag in ~w(l p),
    do: tag |> kept_children(inner) |> Enum.map(&count_breaks(&1, kind)) |> Enum.sum()

  defp count_breaks({_tag, _attrs, inner}, kind),
    do: inner |> Enum.map(&count_breaks(&1, kind)) |> Enum.sum()

  defp count_breaks(_text, _kind), do: 0

  defp count_inline_stage_leaves({_name, _attrs, children}) do
    Enum.reduce(children, 0, fn
      {tag, _attrs, inner}, acc when tag in ~w(l p) ->
        acc + Enum.count(kept_children(tag, inner), &match?({"stage", _, _}, &1))

      {_tag, _, _} = child, acc ->
        acc + count_inline_stage_leaves(child)

      _, acc ->
        acc
    end)
  end

  # The children of an <l> or <p> the importer reads: all of them, but for a line or
  # paragraph all aside, its segs and breaks when it has segs (its stages dropped), and
  # none of its stages and breaks when only a delivery <stage> makes it an aside. One with
  # a word outside its segs is partly aside, and keeps everything.
  defp kept_children(tag, inner) do
    cond do
      not aside_leaf?(tag, inner) -> inner
      not Enum.any?(inner, &aside_seg?/1) -> []
      Enum.any?(inner, &spoken_outside_aside?/1) -> inner
      true -> Enum.filter(inner, &(aside_seg?(&1) or match?({"lb", _, _}, &1)))
    end
  end

  defp aside_seg?({"seg", attrs, _}), do: attr_val(attrs, "type") == "aside"
  defp aside_seg?(_), do: false

  defp spoken_outside_aside?(text) when is_binary(text), do: String.trim(text) != ""

  defp spoken_outside_aside?({name, _, _} = child),
    do: name not in ~w(stage note) and not aside_seg?(child) and String.trim(text_of(child)) != ""

  defp aside_leaf?(tag, inner) do
    Enum.any?(inner, fn
      {"seg", attrs, _} ->
        attr_val(attrs, "type") == "aside"

      {"stage", attrs, _kids} = stage ->
        tag == "l" and delivery?(attrs) and
          Regex.match?(~r/aparte/i, text_of(stage))

      _ ->
        false
    end)
  end

  # The body as a document of its own, for the ImportHelpers readers.
  defp body_doc(xml), do: "<body>" <> extract_body(xml) <> "</body>"

  # Notes with text: an empty <note/> (EMOTHE0010's test file) carries nothing and is
  # rightly not imported.
  defp count_notes(xml),
    do: xml |> body_doc() |> ImportHelpers.xml_notes() |> Enum.count(&(&1.text != ""))

  # Each note as {the element it sits in, the last 12 non-blank characters before it there,
  # n, type}. Blanks are ignored because the importer joins a line's pieces with spaces
  # where an element splits them (a<emph>b</emph> reads "a b"). Only the last characters,
  # because an aside line's delivery <stage> is not exported, so its text no longer
  # precedes the notes after it.
  defp note_anchors(xml) do
    xml
    |> body_doc()
    |> ImportHelpers.xml_notes()
    |> Enum.reject(&(&1.text == ""))
    |> Enum.map(fn note ->
      tail = note.after |> String.replace(~r/\s+/u, "") |> String.slice(-12..-1//1)
      {note.in, tail, note.n, note_type(note.type)}
    end)
  end

  # As the importer reads them: two notes' types are slips (question 17).
  defp note_type("video"), do: "traductor"
  defp note_type("nota_editor_digital"), do: "editor_digital"
  defp note_type(type), do: type

  # No note's text is left in the text it glosses, the bug these checks came with
  # (Hamlet, act 5: a translator's note pasted after "partes …"). Notes under 30
  # characters are skipped: a short gloss may repeat words of the play.
  defp assert_no_pasted_notes(code, original_xml, exported_xml) do
    exported = body_doc(exported_xml)

    text =
      ~w(l p stage speaker head trailer)
      |> Enum.flat_map(&ImportHelpers.reading_texts(exported, &1))
      |> Enum.join()
      |> squash()

    for note <- ImportHelpers.xml_notes(body_doc(original_xml)),
        String.length(note.text) >= 30 do
      refute String.contains?(text, squash(note.text)),
             "#{code}: note #{note.n} is pasted into the text"
    end
  end

  defp squash(text), do: String.replace(text, ~r/\s+/u, "")

  defp xml_escape(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end

  defp assert_export_includes_text(code, exported_xml, label, text)

  defp assert_export_includes_text(_code, _exported_xml, _label, text)
       when is_nil(text) or text == "" do
    :ok
  end

  defp assert_export_includes_text(code, exported_xml, label, text) when is_binary(text) do
    if String.contains?(exported_xml, text) or String.contains?(exported_xml, xml_escape(text)) do
      :ok
    else
      flunk("#{code} #{label}: '#{text}' not found in export")
    end
  end

  defp normalize_ws(text) when is_binary(text) do
    text
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  # Entities are decoded so that D'ATHALIE in the source equals D&apos;ATHALIE in the
  # export (EMOTHE0033, 0752): the same text, spelled two ways.
  defp strip_tags(text) when is_binary(text) do
    text
    |> then(fn t -> Regex.replace(~r/<[^>]+>/u, t, "") end)
    |> decode_entities()
    |> normalize_ws()
  end

  defp decode_entities(text) do
    text
    |> String.replace(~w(&apos; &quot; &lt; &gt;), fn
      "&apos;" -> "'"
      "&quot;" -> "\""
      "&lt;" -> "<"
      "&gt;" -> ">"
    end)
    |> then(
      &Regex.replace(~r/&#(x?)([0-9a-fA-F]+);/, &1, fn _, hex, n ->
        <<String.to_integer(n, if(hex == "x", do: 16, else: 10))::utf8>>
      end)
    )
    |> String.replace("&amp;", "&")
  end

  defp text_of({_name, _attrs, children}) do
    children
    |> Enum.map_join(fn
      t when is_binary(t) -> t
      el -> text_of(el)
    end)
    |> String.trim()
  end

  defp extract_between(xml, open_tag, close_tag) do
    case Regex.run(~r/#{open_tag}(.*)#{close_tag}/s, xml) do
      [_, inner] -> inner
      _ -> ""
    end
  end

  defp character_roles_in_order(xml) do
    cast_list = extract_between(xml, "<castList>", "<\\/castList>")

    Regex.scan(~r/<role\b[^>]*>(.*?)<\/role>/su, cast_list, capture: :all_but_first)
    |> Enum.map(fn
      [role_inner] -> strip_tags(role_inner)
      _ -> ""
    end)
    |> Enum.reject(&(&1 == ""))
  end

  defp source_titles_in_order(xml) do
    source_desc = extract_between(xml, "<sourceDesc>", "<\\/sourceDesc>")

    Regex.scan(~r/<bibl>(.*?)<\/bibl>/su, source_desc, capture: :all_but_first)
    |> Enum.map(fn
      [bibl_inner] ->
        case Regex.run(~r/<title>(.*?)<\/title>/su, bibl_inner, capture: :all_but_first) do
          [title] -> strip_tags(title)
          _ -> ""
        end

      _ ->
        ""
    end)
    |> Enum.reject(&(&1 == ""))
  end

  defp verse_line_tokens_in_order(xml) do
    body = extract_body(xml)

    Regex.scan(~r/<l\b([^>]*)>/u, body, capture: :all_but_first)
    |> Enum.map(fn
      [attrs] ->
        n =
          case Regex.run(~r/\bn="(\d+)"/u, attrs, capture: :all_but_first) do
            [num] -> String.to_integer(num)
            _ -> nil
          end

        part =
          case Regex.run(~r/\bpart="([IMF])"/u, attrs, capture: :all_but_first) do
            [p] -> p
            _ -> nil
          end

        line_id =
          case Regex.run(~r/\bxml:id="([^"]+)"/u, attrs, capture: :all_but_first) do
            [id] -> id
            _ -> nil
          end

        {line_id, n, part}
    end)
  end

  defp distinct_verse_numbers(xml) do
    xml
    |> verse_line_tokens_in_order()
    |> Enum.map(fn {_id, n, _part} -> n end)
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
    |> MapSet.size()
  end

  defp assert_order_preserved(code, label, original_list, exported_list) do
    if original_list != [] do
      assert original_list == exported_list,
             "#{code} ordering mismatch for #{label}: original=#{inspect(original_list)} exported=#{inspect(exported_list)}"
    end
  end

  defp assert_derived_verse_fields(code, play, original_xml, exported_xml) do
    expected = distinct_verse_numbers(original_xml)

    assert play.verse_count == expected,
           "#{code} derived verse_count mismatch: expected=#{expected} got=#{inspect(play.verse_count)}"

    expected_is_verse = expected > 0

    assert play.is_verse == expected_is_verse,
           "#{code} derived is_verse mismatch: expected=#{expected_is_verse} got=#{inspect(play.is_verse)}"

    assert exported_xml =~ ~r/<extent[^>]*>\s*#{expected}\s+versos\s*<\/extent>/u,
           "#{code} export missing computed <extent> for verse_count=#{expected}"
  end

  # Verify that key metadata fields from the DB appear in the exported XML
  defp assert_metadata_roundtrip(code, play, exported_xml) do
    # Play title must appear in export
    assert_export_includes_text(code, exported_xml, "metadata: title", play.title)

    # Author name must appear in export
    assert_export_includes_text(code, exported_xml, "metadata: author", play.author_name)

    # Play code must appear in export
    assert_export_includes_text(code, exported_xml, "metadata: code", play.code)

    # Original title if present
    assert_export_includes_text(
      code,
      exported_xml,
      "metadata: original_title",
      play.original_title
    )

    # Publication place if present
    assert_export_includes_text(code, exported_xml, "metadata: pub_place", play.pub_place)

    # Publication date if present
    assert_export_includes_text(
      code,
      exported_xml,
      "metadata: publication_date",
      play.publication_date
    )

    # Licence URL if present
    assert_export_includes_text(code, exported_xml, "metadata: licence_url", play.licence_url)

    # Source fields: each source's title and author should appear
    for source <- play.sources || [] do
      assert_export_includes_text(code, exported_xml, "source: title", source.title)
      assert_export_includes_text(code, exported_xml, "source: author", source.author)
    end

    # Edition title if present
    assert_export_includes_text(code, exported_xml, "metadata: edition_title", play.edition_title)

    # Author attribution if present (appears as ana= attribute)
    assert_export_includes_text(
      code,
      exported_xml,
      "metadata: author_attribution",
      play.author_attribution
    )

    # Editor names should appear
    for editor <- play.editors || [] do
      assert_export_includes_text(code, exported_xml, "editor", editor.person_name)
    end

    # Principal editor should appear in <principal> tag
    principals = Enum.filter(play.editors || [], &(&1.role == "principal"))

    for p <- principals do
      if p.person_name && p.person_name != "" do
        name_re = Regex.escape(p.person_name)
        escaped_name_re = Regex.escape(xml_escape(p.person_name))

        assert Regex.match?(
                 ~r/<principal>\s*(#{name_re}|#{escaped_name_re})\s*<\/principal>/s,
                 exported_xml
               ),
               "#{code} principal: '#{p.person_name}' not found as <principal> in export"
      end
    end

    # Sponsor should appear if present
    assert_export_includes_text(code, exported_xml, "metadata: sponsor", play.sponsor)

    # Funder should appear if present
    assert_export_includes_text(code, exported_xml, "metadata: funder", play.funder)

    # Language: <language ident="xx-XX"> must start with the play's language code
    if play.language && play.language != "" do
      assert exported_xml =~ ~r/<language\s+ident="#{Regex.escape(play.language)}/,
             "#{code} language: ident starting with '#{play.language}' not found in <language> element"
    end
  end

  @doc """
  Imports the TEI file at `path`, exports it again and asserts the export lost nothing:
  the structure's counts, the metadata, and the order of notes, characters, sources and
  verse lines. Each corpus file's module, at the end of this file, calls it.
  """
  def assert_roundtrip(path) do
    code = Path.basename(path, ".xml")
    original_xml = read_original(path)
    orig_counts = original_xml |> structural_counts() |> closing_scenes_as_trailers(original_xml)

    assert {:ok, play} = Playcode.Import.TeiImport.import_file(path),
           "Failed to import #{path}"

    play_full = Playcode.Catalogue.get_play_with_all!(play.id)
    exported_xml = Playcode.Export.TeiXml.generate(play_full)
    export_counts = structural_counts(exported_xml)

    mismatches =
      for field <- @fields,
          orig_val = Map.fetch!(orig_counts, field),
          export_val = Map.fetch!(export_counts, field),
          orig_val != export_val do
        "  #{field}: original=#{orig_val} exported=#{export_val}"
      end

    assert mismatches == [],
           "#{code} structural mismatches:\n#{Enum.join(mismatches, "\n")}" <>
             "\n\noriginal=#{inspect(orig_counts)}\nexported=#{inspect(export_counts)}"

    assert_metadata_roundtrip(code, play_full, exported_xml)

    assert_order_preserved(
      code,
      "notes (where each sits)",
      note_anchors(original_xml),
      note_anchors(exported_xml)
    )

    assert_no_pasted_notes(code, original_xml, exported_xml)

    assert_order_preserved(
      code,
      "characters (castList role text)",
      character_roles_in_order(original_xml),
      character_roles_in_order(exported_xml)
    )

    assert_order_preserved(
      code,
      "sources (sourceDesc/bibl/title)",
      source_titles_in_order(original_xml),
      source_titles_in_order(exported_xml)
    )

    assert_order_preserved(
      code,
      "verse lines (<l> attrs)",
      verse_line_tokens_in_order(original_xml),
      verse_line_tokens_in_order(exported_xml)
    )

    assert_derived_verse_fields(code, play_full, original_xml, exported_xml)

    # The corpus predates <settingDesc>: a file without one must leave the
    # gazetteer empty, or the places branch of the parser fired on nothing.
    unless original_xml =~ "<settingDesc" do
      assert Playcode.Places.list_places() == []
    end
  end

  describe "places roundtrip" do
    test "export, import and re-export produce the same places" do
      play = Playcode.TestFixtures.play_fixture(%{"code" => "ROUNDPLACE1"})

      # `places.slug` is globally unique, so two async tests inserting the same chain of
      # slugs in different orders deadlock on the index. This test compares one export
      # against another, so the words do not matter — only that they are ours alone.
      ns = "rt#{System.unique_integer([:positive])}"

      italy =
        Playcode.TestFixtures.place_fixture(%{
          "name" => "Italia",
          "type" => "country",
          "slug" => "#{ns}-italia"
        })

      roma =
        Playcode.TestFixtures.place_fixture(%{
          "names" => [
            %{"name" => "Roma", "language" => "es", "is_preferred" => "true"},
            %{"name" => "Rome", "language" => "en", "is_preferred" => "true"}
          ],
          "type" => "city",
          "slug" => "#{ns}-roma",
          "parent_place_id" => italy.id,
          "latitude" => "41.9028",
          "longitude" => "12.4964",
          "authority" => "wikidata",
          "authority_id" => "Q220"
        })

      miseno =
        Playcode.TestFixtures.place_fixture(%{
          "name" => "Miseno",
          "type" => "town",
          "slug" => "#{ns}-miseno",
          "parent_place_id" => italy.id
        })

      Playcode.TestFixtures.play_place_fixture(play, roma, %{"role" => "setting"})

      Playcode.TestFixtures.play_place_fixture(play, miseno, %{
        "role" => "mentioned",
        "note" => "Named, not staged."
      })

      first = Playcode.Export.TeiXml.generate(Playcode.Catalogue.get_play_with_all!(play.id))

      path = Path.join(System.tmp_dir!(), "roundtrip-places.xml")
      File.write!(path, first)
      on_exit(fn -> File.rm(path) end)

      {:ok, reimported} = Playcode.Import.TeiImport.import_file(path)

      second =
        Playcode.Export.TeiXml.generate(Playcode.Catalogue.get_play_with_all!(reimported.id))

      assert settings(second) == settings(first)
      assert place_ids(second) == place_ids(first)
      assert second =~ ~s(<geo>41.9028 12.4964</geo>)
      assert second =~ ~s(<idno type="wikidata">Q220</idno>)
      assert second =~ "Named, not staged."
    end

    defp settings(xml), do: Regex.scan(~r/ref="#([^"]+)" ana="([^"]+)"/, xml)
    defp place_ids(xml), do: Regex.scan(~r/<place xml:id="([^"]+)"/, xml)
  end
end

# One module per corpus file, because a module's tests run one after another: the three
# default plays in one module took 3-5 s and were the tail of the async run. Apart, they
# run side by side, and so does the sweep under `--include slow`.
#
# Three tracked fixtures run on every `mix test`, so CI exercises real corpus files end
# to end: one verse play with scenes, heads, asides, split lines and verse types, one
# prose play, and one with in-text notes (17: on lines and speakers). The rest of the
# tracked fixtures, plus the git-ignored corpus under test/fixtures/tei_files/ when
# present, run with `mix test --include slow`.
default_fixtures = ~w(
  EMOTHE0746_LesOccasionsPerdues.xml
  EMOTHE0776_LosRivales.xml
  EMOTHE0705_LaVirginie.xml
)

{default_paths, slow_paths} =
  (Path.wildcard(Path.expand("../fixtures/*.xml", __DIR__)) ++
     Path.wildcard(Path.expand("../fixtures/tei_files/*.xml", __DIR__)))
  |> Enum.uniq_by(&Path.basename/1)
  |> Enum.sort_by(&Path.basename/1)
  |> Enum.split_with(&(Path.basename(&1) in default_fixtures))

# A whole play is imported in one transaction, CPU-bound in Elixir, so at most one import
# per scheduler runs at a time: modules in one group never run together. The default
# fixtures come first, a lane each.
lanes = System.schedulers_online()

for {path, i} <- Enum.with_index(default_paths ++ slow_paths) do
  code = Path.basename(path, ".xml")
  lane = :"roundtrip_#{rem(i, lanes)}"

  defmodule Module.concat(Playcode.RoundtripTest, code) do
    use Playcode.DataCase, async: true, group: lane

    if path in slow_paths do
      @moduletag :slow
    end

    @moduletag timeout: 120_000
    @path path

    test "roundtrip: #{code}", do: Playcode.RoundtripTest.assert_roundtrip(@path)
  end
end
