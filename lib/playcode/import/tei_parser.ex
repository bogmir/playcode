defmodule Playcode.Import.TeiParser do
  @moduledoc """
  Reads a TEI-XML file into a plain description of a play, touching no database.

  `parse_file/1` returns everything `Playcode.Import.TeiImport` writes, in document order
  and with every position already counted:

      %{
        play: %{code: "EMOTHE0010", title: "…", …},
        editors: [%{person_name, role, organization, position}],
        sources: [%{title, author, editor, editor_role, publisher, pub_place, pub_date,
                    note, language, distributor, position}],
        witnesses: [%{siglum, witness_type, title, …}],
        places: [%{attrs: %{"slug" => …, …}, slug_declared: boolean, places: [place]}],
        settings: [%{slug, role, position, note, state}],
        characters: [%{xml_id, name, description, actor, is_hidden, position}],
        paratexts: [%{kind, heading, content, position, back}],
        performances: [%{date_text, year_from, year_to, venue, venue_type, place, state,
                         company, note, cast: [%{role, surname, forename, nickname, sex}],
                         source, source_volume, source_pages, cast_from_cast_list}],
        divisions: [%{type, number, title, position, notes, elements, divisions}],
        bibliography: [%{description, volume, pages}]
      }

  An element is `%{type, position, notes, elements}` plus its columns, and a speech's
  `who` the xml_ids it names. A reference of the bibliography is its
  `Bibliography.Entry.description/1` and where the play sits in it. A note is `%{offset, n, type, term, body}`. An entry of
  the critical apparatus is a note of type "variante" that also carries `variant_type`,
  `range_end` and `readings` (`%{lemma, wit, text, note}`), its `body` possibly nil. A
  performance is its `place` and `state` as slugs, its `company` plain and its `source` as
  a reference is, `Bibliography.Entry.description/1`, with where the performance sits in
  it (`source_volume`, `source_pages`); a cast row's `sex` is `"man"`, `"woman"` or nil.
  Nothing here knows a row: ids, `play_id` and `origin` are the writer's.

  Handles UTF-16 encoded files (common in the EMOTHE corpus) by converting them to UTF-8
  before parsing with Saxy.
  """

  alias Playcode.Bibliography.Entry
  alias Playcode.Catalogue.Play
  alias Playcode.Performances.Performance
  alias Playcode.Places
  alias Playcode.PlayContent.{Division, InlineMarkup, Note}
  alias Playcode.Text
  alias Playcode.Witnesses

  require Logger

  @title_small_words MapSet.new([
                       "a",
                       "al",
                       "and",
                       "as",
                       "at",
                       "d",
                       "da",
                       "das",
                       "de",
                       "del",
                       "des",
                       "di",
                       "do",
                       "dos",
                       "e",
                       "el",
                       "en",
                       "et",
                       "i",
                       "la",
                       "las",
                       "le",
                       "les",
                       "los",
                       "of",
                       "or",
                       "the",
                       "to",
                       "y"
                     ])

  @doc """
  Reads the play at `path`: `{:ok, tei}` (see the moduledoc) or `{:error, reason}`, the
  reason `File.read/1`'s, `{:xml_parse_error, _}`, `:encoding_error` or
  `:missing_tei_header`.
  """
  def parse_file(path) do
    with {:ok, {_name, _attrs, children}} <- read_tree(path) do
      case find_child(children, "teiHeader") do
        nil ->
          {:error, :missing_tei_header}

        {_name, _attrs, header} ->
          {:ok, Map.merge(header(header), text(find_child(children, "text")))}
      end
    end
  end

  defp read_tree(path) do
    with {:ok, raw} <- File.read(path),
         xml when is_binary(xml) <- normalize_encoding(raw),
         {:ok, tree} <- parse_xml(xml) do
      {:ok, folio_text(tree)}
    else
      {:error, reason} ->
        {:error, reason}

      {:incomplete, _, _} = err ->
        Logger.error("Encoding conversion failed for #{path}: #{inspect(err)}")
        {:error, :encoding_error}

      other ->
        Logger.error("Unexpected error reading #{path}: #{inspect(other)}")
        {:error, other}
    end
  end

  # --- HTML typed as text ---

  # Seven files hold HTML typed into <code> as text (docs/tei-apparatus-and-code.md). On
  # the old site a <span class="folio"> hid Hamlet's Folio passages, each between two
  # superscript F's. A file with such an F has its passages read into <folio> markers
  # (InlineMarkup); a file with none (The Rover, the Spanish version of The Spanish
  # Tragedy) uses the wrapper for nothing the project wants hidden, so it goes and its
  # words stay. An <app type="folio"> of the agreed form is a passage in any file.
  @folio_wrapper [~s(<span class="folio">), "</span>"]
  @folio_label ["<sup>", "F", "</sup>"]

  defp folio_text(tree) do
    tree = folio_apps(tree)

    if folio_labels?(tree),
      do: tree |> passages(false) |> elem(0),
      else: without_folio_wrappers(tree)
  end

  # The form question 36 agreed: an empty <lem wit="#Q2"/> and one <rdg wit="#F1">. The
  # reading's contents go between markers in the text beside the <app>. Any other <app
  # type="folio"> stays an entry of the apparatus, which keeps everything it says.
  defp folio_apps({name, attrs, children}) do
    children = Enum.map(children, &folio_apps/1)

    if Enum.any?(children, &folio_app?/1) do
      children =
        Enum.flat_map(children, fn
          {"app", _, readings} = app ->
            if folio_app?(app),
              do: ["<folio>" | folio_reading(readings)] ++ ["</folio>"],
              else: [app]

          child ->
            [child]
        end)

      {name, attrs, merge_text(children)}
    else
      {name, attrs, children}
    end
  end

  defp folio_apps(text), do: text

  # A reading with no word would be an empty passage, which the line refuses: that app
  # stays an entry.
  defp folio_app?({"app", [{"type", "folio"}], children}) do
    case Enum.reject(children, &blank?/1) do
      [{"lem", [{"wit", "#Q2"}], lem}, {"rdg", [{"wit", "#F1"}], words}] ->
        Enum.all?(lem, &blank?/1) and text_content({"rdg", [], without(words, "note")}) != ""

      _ ->
        false
    end
  end

  defp folio_app?(_), do: false

  defp folio_reading(readings) do
    {"rdg", _, words} = Enum.find(readings, &match?({"rdg", _, _}, &1))
    words
  end

  defp blank?(child), do: is_binary(child) and String.trim(child) == ""

  # Whether the file has an F label, which is what makes it Hamlet's. `label?/3` reads a
  # label of any word on purpose: one passage closes with "and" (v. 3315).
  defp folio_labels?({_name, _attrs, children}) do
    labelled =
      children
      |> Enum.map(&typed_text/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.chunk_every(3, 1, :discard)
      |> Enum.member?(@folio_label)

    labelled or Enum.any?(children, &folio_labels?/1)
  end

  defp folio_labels?(_text), do: false

  # Elements whose children are elements of the text, not its words.
  @folio_containers ~w(TEI text front body back group div div1 div2 div3 div4 div5 sp lg)

  # `node` with its Folio passages read, and whether a passage is open after it, threaded
  # through the tree in document order. A passage runs from one superscript label to the
  # next, whatever the spans say (Hamlet's file misplaces two): the labels become markers in
  # the text nodes beside them, so the words keep their spacing, and the spans go.
  defp passages({name, attrs, children}, inside) when name in @folio_containers do
    {children, inside} = Enum.map_reduce(children, inside, &passages/2)
    {{name, attrs, children}, inside}
  end

  defp passages({name, attrs, children} = element, inside) do
    if inside or labelled?(element) do
      {marks, still_inside} = label_marks(children, inside)
      attrs = attrs ++ folio_edges(inside, still_inside, marks)
      {{name, attrs, marks |> folio_tags() |> merge_text()}, still_inside}
    else
      {without_folio_wrappers(element), inside}
    end
  end

  defp passages(text, inside), do: {text, inside}

  defp labelled?({_name, _attrs, children}) do
    children |> Enum.chunk_every(3, 1, :discard) |> Enum.any?(fn [a, b, c] -> label?(a, b, c) end) or
      Enum.any?(children, &(is_tuple(&1) and labelled?(&1)))
  end

  defp labelled?(_text), do: false

  # <sup>, its text, </sup>, each typed as text: an F, or once in Hamlet "and" (v. 3315).
  defp label?(open, text, close),
    do: typed_text(open) == "<sup>" and is_binary(text) and typed_text(close) == "</sup>"

  # The children with each label an :open or a :close (its words, when they are not the F,
  # kept inside the passage) and the spans dropped. A child read while no passage is open
  # may hold one of its own (a <seg> aside); one read inside a passage goes in whole.
  defp label_marks([a, b, c | rest] = children, inside) do
    if label?(a, b, c) do
      label =
        case {String.trim(b), inside} do
          {"F", true} -> [:close]
          {"F", false} -> [:open]
          {words, true} -> [" " <> words, :close]
          {words, false} -> [:open, words <> " "]
        end

      {marks, inside} = label_marks(rest, not inside)
      {label ++ marks, inside}
    else
      next_mark(children, inside)
    end
  end

  defp label_marks(children, inside), do: next_mark(children, inside)

  defp next_mark([], inside), do: {[], inside}

  defp next_mark([child | rest], inside) do
    {child, inside} =
      cond do
        typed_text(child) in @folio_wrapper ->
          {[], inside}

        is_tuple(child) and not inside ->
          child |> passages(false) |> then(fn {c, i} -> {[c], i} end)

        is_tuple(child) ->
          {[without_folio_wrappers(child)], inside}

        true ->
          {[child], inside}
      end

    {marks, inside} = label_marks(rest, inside)
    {child ++ marks, inside}
  end

  # The attributes that say a passage open before this element runs into it, and one open
  # after it runs out of it: its text, once read, starts with <folio part="F"> (part "M"
  # when no label here closes it) and ends with </folio> (with_folio_edges/2).
  @folio_lead "playcode-folio-lead"
  @folio_trail "playcode-folio-trail"

  defp folio_edges(inside, still_inside, marks) do
    lead =
      cond do
        inside and :close not in marks -> [{@folio_lead, "M"}]
        inside -> [{@folio_lead, "F"}]
        true -> []
      end

    if still_inside, do: lead ++ [{@folio_trail, "true"}], else: lead
  end

  # The marks as marker text: a passage opened and closed here is <folio>…</folio>; one
  # opened here and still open at the end is part "I", closed when the text is read.
  defp folio_tags(marks) do
    {tags, _closed_later} =
      marks
      |> Enum.reverse()
      |> Enum.map_reduce(false, fn
        :close, _closed_later -> {"</folio>", true}
        :open, true -> {"<folio>", false}
        :open, false -> {~s(<folio part="I">), false}
        other, closed_later -> {other, closed_later}
      end)

    Enum.reverse(tags)
  end

  # `text`, the text of an element read, with the edges its passage gives it.
  defp with_folio_edges(text, _attrs) when text in [nil, ""], do: text

  defp with_folio_edges(text, attrs) do
    lead =
      case attr_value(attrs, @folio_lead) do
        nil -> ""
        part -> ~s(<folio part="#{part}">)
      end

    trail = if attr_value(attrs, @folio_trail), do: "</folio>", else: ""
    lead <> text <> trail
  end

  # Touching text nodes as one, so a marker sits against the words beside it.
  defp merge_text(children) do
    children
    |> Enum.chunk_by(&is_binary/1)
    |> Enum.flat_map(fn
      [text | _] = texts when is_binary(text) -> [Enum.join(texts)]
      elements -> elements
    end)
  end

  defp without_folio_wrappers({name, attrs, children}) do
    {name, attrs,
     for(
       child <- children,
       typed_text(child) not in @folio_wrapper,
       do: without_folio_wrappers(child)
     )}
  end

  defp without_folio_wrappers(text), do: text

  # A <code>'s text or a text node, trimmed; nil for any other element.
  defp typed_text({"code", _attrs, children}),
    do: children |> Enum.filter(&is_binary/1) |> Enum.join() |> String.trim()

  defp typed_text(text) when is_binary(text), do: String.trim(text)
  defp typed_text(_element), do: nil

  # --- Encoding ---

  defp normalize_encoding(raw) do
    # Detect UTF-16 BOM (little-endian or big-endian)
    case raw do
      <<0xFF, 0xFE, rest::binary>> ->
        :unicode.characters_to_binary(rest, {:utf16, :little})

      <<0xFE, 0xFF, rest::binary>> ->
        :unicode.characters_to_binary(rest, {:utf16, :big})

      # Check for null bytes pattern typical of UTF-16LE without BOM
      <<first, 0x00, _rest::binary>> when first != 0x00 ->
        :unicode.characters_to_binary(raw, {:utf16, :little})

      # UTF-8 BOM
      <<0xEF, 0xBB, 0xBF, rest::binary>> ->
        rest

      _ ->
        raw
    end
  end

  # --- XML Parsing ---

  defp parse_xml(xml) do
    # Strip XML declaration and stylesheet processing instructions
    xml = String.replace(xml, ~r/<\?xml[^?]*\?>/, "")
    xml = String.replace(xml, ~r/<\?xml-stylesheet[^?]*\?>/, "")
    xml = String.trim(xml)

    case Saxy.SimpleForm.parse_string(xml) do
      {:ok, tree} -> {:ok, tree}
      {:error, reason} -> {:error, {:xml_parse_error, reason}}
    end
  end

  # --- Header ---

  defp header(children) do
    file_desc = find_child(children, "fileDesc")
    profile_desc = find_child(children, "profileDesc")

    %{
      play:
        file_desc
        |> extract_play_attrs(find_child(children, "encodingDesc"), profile_desc)
        |> Map.put(:revisions, revisions(find_child(children, "revisionDesc"))),
      editors: editors(file_desc),
      sources: sources(file_desc),
      witnesses: witnesses(file_desc),
      places: places(profile_desc),
      settings: settings(profile_desc)
    }
  end

  defp extract_play_attrs(file_desc, encoding_desc, profile_desc) do
    title_stmt = file_desc && find_child(elem(file_desc, 2), "titleStmt")
    publication_stmt = file_desc && find_child(elem(file_desc, 2), "publicationStmt")
    extent = file_desc && find_child(elem(file_desc, 2), "extent")

    titles = if title_stmt, do: find_children(elem(title_stmt, 2), "title"), else: []
    authors = if title_stmt, do: find_children(elem(title_stmt, 2), "author"), else: []

    # The main title: the one that says what kind of play this is (question 15), else the
    # first with no key or type, else the first with no key.
    kind_title =
      Enum.find(titles, fn {_, attrs, _} ->
        attr_value(attrs, "type") in Play.relationship_types()
      end)

    plain_title =
      Enum.find(titles, fn {_, attrs, _} ->
        !has_attr?(attrs, "key") and !has_attr?(attrs, "type")
      end)

    main_title =
      kind_title || plain_title ||
        Enum.find(titles, fn {_, attrs, _} -> !has_attr?(attrs, "key") end)

    sort_title = Enum.find(titles, fn {_, attrs, _} -> attr_value(attrs, "key") == "orden" end)
    code_title = Enum.find(titles, fn {_, attrs, _} -> attr_value(attrs, "key") == "archivo" end)

    original_title_el =
      Enum.find(titles, fn {_, attrs, _} -> attr_value(attrs, "type") == "original" end)

    edition_title_el =
      Enum.find(titles, fn {_, attrs, _} -> attr_value(attrs, "type") == "edicion" end)

    relationship_type = kind_title && attr_value(elem(kind_title, 1), "type")

    # Extract sponsor and funder from titleStmt
    sponsor_el = if title_stmt, do: find_child(elem(title_stmt, 2), "sponsor"), else: nil
    funder_el = if title_stmt, do: find_child(elem(title_stmt, 2), "funder"), else: nil

    main_author = Enum.find(authors, fn {_, attrs, _} -> !has_attr?(attrs, "key") end)
    sort_author = Enum.find(authors, fn {_, attrs, _} -> attr_value(attrs, "key") == "orden" end)

    # Extract code from either archivo title or idno
    code = if code_title, do: text_content(code_title), else: extract_idno(publication_stmt)

    # Extract verse count from extent
    verse_count = if extent, do: extract_verse_count(extent), else: nil

    # Extract publication info
    {pub_place, pub_date, publisher_text, availability, licence_url, licence_text, authority_text} =
      extract_publication(publication_stmt)

    # Extract EMOTHE-specific idno
    emothe_id = extract_emothe_idno(publication_stmt)

    # Extract project/editorial from encodingDesc
    {project_desc, editorial_decl} = extract_encoding(encoding_desc)

    # Extract play language from profileDesc/langUsage/language[@ident]
    language = extract_language_code(profile_desc)

    {composition_from, composition_to, composition_note} = extract_creation(profile_desc)
    {historical_time, historical_time_note} = extract_historical_time(profile_desc)

    attribution =
      if main_author do
        attr_value(elem(main_author, 1), "ana")
      end

    title = safe_text(main_title) |> normalize_imported_title()

    %{
      title: title,
      title_sort: safe_text(sort_title) |> normalize_sort_title(title),
      code: clean_code(code || "UNKNOWN"),
      original_title: safe_text(original_title_el),
      author_name: safe_text(main_author),
      author_sort: safe_text(sort_author),
      author_attribution: attribution,
      verse_count: verse_count,
      is_verse: verse_count != nil && verse_count > 0,
      pub_place: pub_place,
      publication_date: pub_date,
      publisher: publisher_text,
      availability_note: availability,
      licence_url: licence_url,
      licence_text: licence_text,
      emothe_id: emothe_id,
      sponsor: safe_text(sponsor_el),
      funder: safe_text(funder_el),
      authority: authority_text,
      project_description: project_desc,
      editorial_declaration: editorial_decl,
      edition_title: safe_text(edition_title_el),
      relationship_type: relationship_type,
      pending_original_code: original_code(file_desc),
      edition_notes: edition_notes(file_desc),
      language: language || "es",
      composition_date_from: composition_from,
      composition_date_to: composition_to,
      composition_date_note: composition_note,
      historical_time: historical_time,
      historical_time_note: historical_time_note
    }
  end

  # Extract the 2-letter language code from profileDesc/langUsage/language[@ident]
  # e.g. ident="it-IT" -> "it", ident="fr-FR" -> "fr"
  defp extract_language_code(nil), do: nil

  defp extract_language_code({_name, _attrs, children}) do
    with lang_usage when not is_nil(lang_usage) <- find_child(children, "langUsage"),
         lang_el when not is_nil(lang_el) <- find_child(elem(lang_usage, 2), "language"),
         ident when not is_nil(ident) <- attr_value(elem(lang_el, 1), "ident"),
         code <- ident |> String.split("-") |> List.first() |> String.downcase(),
         true <- code in Play.valid_languages() do
      code
    else
      _ -> nil
    end
  end

  # profileDesc/creation/date. @when is a single year; @notBefore + @notAfter a range.
  #
  # Anything the changeset would reject is dropped here instead — a lone endpoint, an
  # inverted range, a year outside `Play.composition_year_range/0`. The changeset's
  # strictness is right for curator input, but an unusable attribute in a TEI file must
  # not roll back the import: a rollback discards the text, the characters and the acts
  # too. Per the S2c spec, a file that carries no machine dating is the
  # file's problem, not an import failure. The date's words are the note either way: with
  # no usable year they are a dating in words.
  defp extract_creation(nil), do: {nil, nil, nil}

  defp extract_creation({_name, _attrs, children}) do
    with creation when not is_nil(creation) <- find_child(children, "creation"),
         date when not is_nil(date) <- find_child(elem(creation, 2), "date") do
      {from, to} = creation_years(elem(date, 1))

      if usable_creation_years?(from, to),
        do: {from, to, non_blank_text(date)},
        else: {nil, nil, non_blank_text(date)}
    else
      _ -> {nil, nil, nil}
    end
  end

  defp usable_creation_years?(from, to) do
    range = Play.composition_year_range()
    from in range and to in range and from <= to
  end

  defp creation_years(attrs) do
    case creation_year(attr_value(attrs, "when")) do
      nil ->
        {creation_year(attr_value(attrs, "notBefore")),
         creation_year(attr_value(attrs, "notAfter"))}

      exact ->
        {exact, exact}
    end
  end

  defp creation_year(nil), do: nil

  defp creation_year(value) do
    case Integer.parse(String.trim(value)) do
      {year, _rest} -> year
      :error -> nil
    end
  end

  defp non_blank_text(element) do
    case element |> text_content() |> String.trim() do
      "" -> nil
      text -> text
    end
  end

  # settingDesc/setting/time: the period as @type, its note as the text. A period the
  # changeset would reject is dropped, as an unusable creation year is, and the words kept.
  defp extract_historical_time(profile_desc) do
    with {_name, _attrs, children} <- setting_desc_child(profile_desc, "setting"),
         {_name, attrs, _children} = time <- find_child(children, "time") do
      period = attr_value(attrs, "type")
      {if(period in Play.historical_times(), do: period), non_blank_text(time)}
    else
      nil -> {nil, nil}
    end
  end

  defp extract_idno(nil), do: nil

  defp extract_idno({_name, _attrs, children}) do
    idno = find_child(children, "idno")
    if idno, do: text_content(idno), else: nil
  end

  # Extract the EMOTHE-specific idno (type="EMOTHE")
  defp extract_emothe_idno(nil), do: nil

  defp extract_emothe_idno({_name, _attrs, children}) do
    idnos = find_children(children, "idno")

    emothe_idno =
      Enum.find(idnos, fn {_, attrs, _} -> attr_value(attrs, "type") == "EMOTHE" end)

    if emothe_idno, do: text_content(emothe_idno), else: nil
  end

  # <notesStmt><note>: the notes on the edition, a <lb/> a line break in one.
  defp edition_notes(nil), do: []

  defp edition_notes({_name, _attrs, children}) do
    case find_child(children, "notesStmt") do
      {_, _, notes} -> notes |> find_children("note") |> Enum.map(&lines_text/1)
      nil -> []
    end
  end

  # <revisionDesc><change>: who revised the file and when, as the files write it: a <date>,
  # the revisers' <persName>s and the words saying what was done (the rest of its text,
  # italics as <<…>>), or a <note> saying it. A change with nothing in it (an empty <date/>
  # alone, 44 files) is no change.
  # ponytail: one date, one note and the words after the revisers, the shape of all 351
  # files; a change written as prose around its persNames, with a second note, or dated
  # by @when needs a field of mixed content instead.
  defp revisions(nil), do: []

  defp revisions({_name, _attrs, children}) do
    children
    |> find_children("change")
    |> Enum.map(fn {name, attrs, parts} ->
      %{
        date: safe_text(find_child(parts, "date")),
        people: people(find_children(parts, "persName")),
        description:
          safe_text(
            {name, attrs, parts |> without("date") |> without("persName") |> without("note")}
          ),
        note: safe_text(find_child(parts, "note"))
      }
    end)
    |> Enum.reject(fn change -> change |> Map.values() |> Enum.all?(&(&1 in [nil, ""])) end)
  end

  # <notesStmt><relatedItem type="original" target="EMOTHE0530"/>: the play this one
  # translates, by its short code. The import waits for it
  # (Catalogue.link_waiting_translations/0).
  defp original_code(nil), do: nil

  defp original_code({_name, _attrs, children}) do
    with {_, _, notes} <- find_child(children, "notesStmt"),
         {_, attrs, _} <-
           notes
           |> find_children("relatedItem")
           |> Enum.find(&(attr_value(elem(&1, 1), "type") == "original")),
         target when is_binary(target) <- attr_value(attrs, "target"),
         code when code != "" <- target |> String.trim() |> Play.short_code() do
      code
    else
      _ -> nil
    end
  end

  defp extract_verse_count({_name, _attrs, _children} = extent) do
    text = text_content(extent)

    case Regex.run(~r/(\d+)/, text) do
      [_, num] -> String.to_integer(num)
      _ -> nil
    end
  end

  defp extract_publication(nil), do: {nil, nil, nil, nil, nil, nil, nil}

  defp extract_publication({_name, _attrs, children}) do
    pub_place = find_child(children, "pubPlace")
    date = find_child(children, "date")
    publisher = find_child(children, "publisher")
    availability = find_child(children, "availability")
    authority = find_child(children, "authority")

    # Extract licence details from within availability
    {licence_url, licence_text} =
      case availability do
        {_, _, avail_children} ->
          licence_el = find_child(avail_children, "licence")

          case licence_el do
            {_, attrs, _} ->
              url = attr_value(attrs, "target")
              text = text_content(licence_el)
              {url, text}

            _ ->
              {nil, nil}
          end

        _ ->
          {nil, nil}
      end

    # availability_note: only the <p> text, not the licence text
    availability_text = paragraphs(availability)

    {
      safe_text(pub_place),
      safe_text(date),
      safe_text(publisher),
      availability_text,
      licence_url,
      licence_text,
      safe_text(authority)
    }
  end

  defp extract_encoding(nil), do: {nil, nil}

  defp extract_encoding({_name, _attrs, children}) do
    project_desc = find_child(children, "projectDesc")
    editorial_decl = find_child(children, "editorialDecl")

    # Paragraphs nested deeper (<normalization><p>, which no corpus file has) read as one.
    {
      paragraphs(project_desc) || safe_text(project_desc),
      paragraphs(editorial_decl) || safe_text(editorial_decl)
    }
  end

  # The <p>s of an element, parted by a blank line; nil when they hold no text.
  defp paragraphs(nil), do: nil

  defp paragraphs({_name, _attrs, children}) do
    children
    |> find_children("p")
    |> Enum.map(&text_content/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
    |> case do
      "" -> nil
      text -> text
    end
  end

  # --- Editors ---

  # The principal investigators first (the files write them last), then the titleStmt's
  # <editor>s and respStmts in their order, from position 100, the range the export
  # writes back to the titleStmt, then the editionStmt's respStmts, from 200.
  defp editors(nil), do: []

  defp editors({_name, _attrs, children}) do
    title_stmt = find_child(children, "titleStmt")

    numbered(statement_credits(title_stmt, ~w(principal)), 0) ++
      numbered(statement_credits(title_stmt, ~w(editor respStmt)), 100) ++
      numbered(statement_credits(find_child(children, "editionStmt"), ~w(respStmt)), 200)
  end

  # The credits a statement's `tags` give, in their order.
  defp statement_credits(nil, _tags), do: []

  defp statement_credits({_name, _attrs, children}, tags) do
    Enum.flat_map(children, fn
      {tag, attrs, tag_children} -> if tag in tags, do: credit(tag, attrs, tag_children), else: []
      _text -> []
    end)
  end

  defp credit("principal", attrs, children),
    do: [%{person_name: text_content({"principal", attrs, children}), role: "principal"}]

  defp credit("editor", attrs, children), do: title_editor(attrs, children)
  defp credit("respStmt", _attrs, children), do: resp_stmt_editors(children)

  defp numbered(editors, first) do
    editors
    |> Enum.with_index(first)
    |> Enum.map(fn {editor, position} -> Map.put(editor, :position, position) end)
  end

  # <editor role="…"> in titleStmt: translators, researchers and the editor of the
  # critical edition the text is based on. Any other role (canon60) is skipped.
  defp title_editor(attrs, children) do
    case editor_role(attr_value(attrs, "role")) do
      nil ->
        []

      role ->
        # Name may be in <persName> or direct text
        person_name =
          case find_child(children, "persName") do
            nil -> text_content({"editor", attrs, children})
            el -> text_content(el)
          end

        [
          %{
            person_name: person_name,
            role: role,
            organization: safe_text(find_child(children, "orgName"))
          }
        ]
    end
  end

  defp editor_role("translator"), do: "translator"
  defp editor_role("traductor"), do: "translator"
  defp editor_role("researcher"), do: "researcher"
  defp editor_role("edicion_critica"), do: "critical_editor"
  defp editor_role(_role), do: nil

  # Every <persName> of a respStmt, one editor each, sharing its resp and orgName.
  defp resp_stmt_editors(children) do
    role = resp_role(safe_text(find_child(children, "resp")))
    organization = safe_text(find_child(children, "orgName"))

    children
    |> find_children("persName")
    |> Enum.map(&%{person_name: text_content(&1), role: role, organization: organization})
  end

  defp resp_role(resp) when is_binary(resp) do
    cond do
      String.contains?(resp, "Edición") -> "editor"
      String.contains?(resp, "Revisión") -> "reviewer"
      true -> "digital_editor"
    end
  end

  defp resp_role(nil), do: "digital_editor"

  # --- Sources ---

  # <bibl> directly under <sourceDesc>, or inside <listBibl>.
  defp sources(nil), do: []

  defp sources({_name, _attrs, children}) do
    case find_child(children, "sourceDesc") do
      nil ->
        []

      {_name, _attrs, desc_children} ->
        bibls =
          case find_child(desc_children, "listBibl") do
            nil -> find_children(desc_children, "bibl")
            {_name, _attrs, list_children} -> find_children(list_children, "bibl")
          end

        bibls |> Enum.with_index() |> Enum.map(&source/1)
    end
  end

  defp source({{_name, _attrs, children}, position}) do
    editor_el = find_child(children, "editor")

    %{
      title: safe_text(find_child(children, "title")),
      author: safe_text(find_child(children, "author")),
      editor: safe_text(editor_el),
      editor_role: editor_el && attr_value(elem(editor_el, 1), "role"),
      publisher: safe_text(find_child(children, "publisher")),
      pub_place: safe_text(find_child(children, "pubPlace")),
      pub_date: safe_text(find_child(children, "date")),
      note: safe_text(find_child(children, "note")),
      language: safe_text(find_child(children, "lang")),
      distributor: safe_text(find_child(children, "distributor")),
      position: position
    }
  end

  # --- Witnesses ---

  # `sourceDesc/listWit`, nested lists read in order (S3). Which of them the play keeps
  # depends on the sigla it already has, so that is the writer's call.
  defp witnesses(nil), do: []

  defp witnesses({_name, _attrs, children}) do
    with {_name, _attrs, desc_children} <- find_child(children, "sourceDesc"),
         {_name, _attrs, _children} = list_wit <- find_child(desc_children, "listWit") do
      list_wit |> witness_elements() |> Enum.map(&witness_attrs/1)
    else
      nil -> []
    end
  end

  defp witness_elements({_name, _attrs, children}) do
    Enum.flat_map(children, fn
      {"witness", _, _} = witness -> [witness]
      {"listWit", _, _} = nested -> witness_elements(nested)
      _other -> []
    end)
  end

  # A <bibl> written field by field, as the export writes one, maps back to its columns.
  # Plain words (EMOTHE0460's "anon. [no title page]. London: printed by Richard Pynson…")
  # are kept whole as the note rather than guessed into fields.
  defp witness_attrs({"witness", attrs, children}) do
    {bibl_attrs, parts} =
      case find_child(children, "bibl") do
        {_, bibl_attrs, bibl_children} -> {bibl_attrs, bibl_children}
        nil -> {[], children}
      end

    base = %{
      siglum: attr_value(attrs, "n") || attr_value(attrs, "xml:id"),
      witness_type:
        Witnesses.type_from_tei(attr_value(bibl_attrs, "type"), attr_value(bibl_attrs, "subtype"))
    }

    if Enum.any?(
         parts,
         &match?(
           {name, _, _} when name in ~w(title author pubPlace publisher date extent idno),
           &1
         )
       ) do
      Map.merge(base, %{
        title: parts |> typed("title", nil) |> lines_text(),
        normalized_title: parts |> typed("title", "normalized") |> lines_text(),
        attribution: lines_text(find_child(parts, "author")),
        pub_place: lines_text(find_child(parts, "pubPlace")),
        publisher: lines_text(find_child(parts, "publisher")),
        date: safe_text(find_child(parts, "date")),
        format: lines_text(find_child(parts, "extent")),
        shelfmark: parts |> typed("idno", "shelfmark") |> safe_text(),
        note: lines_text(find_child(parts, "note"))
      })
    else
      Map.put(base, :note, text_content({"bibl", [], parts}))
    end
  end

  # A witness's field with each <lb/> read as a line break, the rest as text_content/1
  # reads it.
  defp lines_text(nil), do: nil

  defp lines_text({name, attrs, children}) do
    children
    |> Enum.chunk_while(
      [],
      fn
        {"lb", _, _}, line -> {:cont, Enum.reverse(line), []}
        child, line -> {:cont, [child | line]}
      end,
      &{:cont, Enum.reverse(&1), []}
    )
    |> Enum.map_join("\n", &text_content({name, attrs, &1}))
  end

  # The first `name` child whose @type is `type` (nil: no @type).
  defp typed(children, name, type), do: with_attr(children, name, "type", type)

  # The first `name` child whose `attr` is `value` (nil: no such attribute).
  defp with_attr(children, name, attr, value),
    do: children |> find_children(name) |> Enum.find(&(attr_value(elem(&1, 1), attr) == value))

  # --- Places ---

  # `listPlace` supplies the places and their containment; `setting` supplies this
  # play's links. Reading them separately is what keeps a pure container — Italia in
  # `<place xml:id="italia">…<place xml:id="roma">` — from becoming a setting.
  defp places(profile_desc) do
    case setting_desc_child(profile_desc, "listPlace") do
      nil -> []
      list_place -> list_places(list_place)
    end
  end

  defp settings(profile_desc) do
    case setting_desc_child(profile_desc, "setting") do
      nil -> []
      setting -> setting_links(setting)
    end
  end

  defp setting_desc_child(nil, _name), do: nil

  defp setting_desc_child({_name, _attrs, children}, name) do
    with {_n, _a, setting_children} <- find_child(children, "settingDesc"),
         do: find_child(setting_children, name)
  end

  defp list_places({_name, _attrs, children}) do
    for {"place", _, _} = place <- children, do: place(place)
  end

  # A place and the places nested in it. `slug_declared` is false when the slug was
  # derived from the name, which the writer warns about if it finds that slug taken.
  defp place({_name, attrs, children} = place_el) do
    declared_slug = attr_value(attrs, "xml:id")
    {latitude, longitude} = place_geo(children)

    place_attrs =
      %{
        "slug" => declared_slug || Places.slugify(first_place_name(children)),
        "type" => attr_value(attrs, "type") || "other",
        "is_fictional" => attr_value(attrs, "subtype") == "fictional",
        "latitude" => latitude,
        "longitude" => longitude,
        "note" => place_note(children),
        "names" => place_names(children)
      }
      |> Map.merge(place_idno(children))

    %{attrs: place_attrs, slug_declared: declared_slug != nil, places: list_places(place_el)}
  end

  defp place_names(children) do
    children
    |> Enum.filter(&match?({"placeName", _, _}, &1))
    |> Enum.with_index()
    |> Enum.map(fn {{_n, attrs, _c} = el, index} ->
      language = attr_value(attrs, "xml:lang")

      %{
        "name" => text_content(el),
        "language" => language,
        "is_historical" => attr_value(attrs, "type") == "historical",
        "is_preferred" => attr_value(attrs, "type") != "historical",
        "position" => index
      }
    end)
    |> Enum.reject(&(&1["name"] in [nil, ""]))
    |> dedupe_preferred()
  end

  # The partial index allows one preferred name per language; a file with two
  # non-historical names in the same language would violate it, so the first wins.
  defp dedupe_preferred(names) do
    {names, _seen} =
      Enum.map_reduce(names, MapSet.new(), fn name, seen ->
        key = name["language"]

        if name["is_preferred"] and not MapSet.member?(seen, key) do
          {name, MapSet.put(seen, key)}
        else
          {Map.put(name, "is_preferred", false), seen}
        end
      end)

    names
  end

  defp first_place_name(children) do
    case Enum.find(children, &match?({"placeName", _, _}, &1)) do
      nil -> "place"
      el -> text_content(el)
    end
  end

  defp place_geo(children) do
    with {_n, _a, location_children} <- find_child(children, "location"),
         geo when not is_nil(geo) <- find_child(location_children, "geo"),
         [lat, long] <- geo |> text_content() |> String.split(~r/\s+/, trim: true),
         {latitude, _} <- Float.parse(lat),
         {longitude, _} <- Float.parse(long) do
      {latitude, longitude}
    else
      _ -> {nil, nil}
    end
  end

  defp place_idno(children) do
    case find_child(children, "idno") do
      {_n, attrs, _c} = el ->
        authority = attr_value(attrs, "type")

        if authority in Places.Place.authorities() do
          %{"authority" => authority, "authority_id" => text_content(el)}
        else
          %{}
        end

      _ ->
        %{}
    end
  end

  # A place's own note is `<note type="place">`, a direct child of `<place>`. Do not
  # match a bare `<note>` here — that shape belongs to a link's note nested inside
  # `<setting>/<placeName>` (see setting_note/1), one level deeper and without the
  # type attribute. See task-10-report.md for the export side of this contract.
  defp place_note(children) do
    case Enum.find(children, &match?({"note", _, _}, &1)) do
      {_n, attrs, _c} = el ->
        if attr_value(attrs, "type") == "place" do
          text_content(el)
        else
          Logger.info("TEI import: <note> under <place> without type=\"place\", skipped")
          nil
        end

      nil ->
        nil
    end
  end

  defp setting_links({_name, _attrs, children}) do
    children
    |> Enum.filter(&match?({"placeName", _, _}, &1))
    |> Enum.with_index()
    |> Enum.map(fn {{_n, attrs, name_children}, index} ->
      %{
        slug: ref_slug(attrs),
        role: attr_value(attrs, "ana") || "setting",
        position: index,
        note: setting_note(name_children),
        state: setting_state(name_children)
      }
    end)
  end

  # A link's historical state is the `ref` of its first `<country>` or nested
  # `<placeName>`: a nested one is the state, not another link.
  defp setting_state(children) do
    state = Enum.find(children, &match?({name, _, _} when name in ["country", "placeName"], &1))

    case state && state |> elem(1) |> ref_slug() do
      "" -> nil
      slug -> slug
    end
  end

  defp ref_slug(attrs), do: attrs |> attr_value("ref") |> to_string() |> String.trim_leading("#")

  # A link's note is a bare `<note>` inside `<setting>/<placeName>` — no `type`
  # attribute, and one tree level deeper than a place's own `<note type="place">`.
  defp setting_note(children) do
    case find_child(children, "note") do
      nil -> nil
      el -> text_content(el)
    end
  end

  # --- Text (front, body) ---

  defp text(nil),
    do: %{characters: [], paratexts: [], divisions: [], bibliography: [], performances: []}

  # The front, the body and the back are read child by child onto one position counter:
  # a play's top-level paratexts and divisions share one order, the file's (`Outline`).
  # In the front a div, the <set> and a bare <castList> each take a position; in the body
  # every div1; in the back every div but the bibliography. The title page and the
  # performances take none.
  defp text({_name, _attrs, children}) do
    front = find_child(children, "front")
    back = find_child(children, "back")

    items =
      (slots(:front, front) ++ slots(:body, find_child(children, "body")) ++ slots(:back, back))
      |> Enum.with_index()
      |> Enum.flat_map(fn {slot, pos} -> read_slot(slot, pos) end)

    divisions = for {:division, division} <- items, do: division

    %{
      characters: declared_characters(divisions),
      paratexts: for({:paratext, paratext} <- items, do: paratext),
      divisions: divisions,
      bibliography: bibliography(back),
      performances:
        for({"performance", attrs, parts} <- children_of(front), do: performance(attrs, parts))
    }
  end

  # Each child that takes a position: {section, element name, type, attributes, children}.
  defp slots(section, element) do
    for {name, attrs, children} = child <- children_of(element), slot?(section, child) do
      type = (attr_value(attrs, "type") || default_type(name)) |> String.downcase()
      {section, name, type, attrs, children}
    end
  end

  defp default_type("div1"), do: "acto"
  defp default_type(_name), do: "front"

  defp slot?(:front, {name, _, _}), do: name in ~w(div set castList)
  defp slot?(:body, {name, _, _}), do: name in ~w(div1 div)

  defp slot?(:back, {"div", attrs, _children}), do: attr_value(attrs, "type") != "bibliografia"

  defp slot?(_section, _child), do: false

  defp read_slot({_section, "castList", _type, _attrs, children}, pos),
    do: [{:division, cast_list(find_child(children, "head"), children, pos)}]

  defp read_slot({_section, _name, "elenco", _attrs, children}, pos),
    do: [{:division, elenco(children, pos)}]

  defp read_slot({_section, "set", _type, _attrs, children}, pos),
    do: for(scene <- paratext("lugar_accion", children, pos), do: {:paratext, scene})

  defp read_slot({:body, _name, type, attrs, children} = slot, pos) do
    if paratext_div1?(type, attrs, children),
      do: read_slot(put_elem(slot, 0, :front), pos),
      else: [{:division, act(type, attrs, children, pos)}]
  end

  defp read_slot({_section, _name, type, _attrs, children}, pos) do
    for paratext <- paratext(type, children, pos), do: {:paratext, paratext}
  end

  # A div1 between the acts holding only what a paratext holds (a heading, paragraphs or
  # stanzas, a closing formula) is a paratext, as Playcode writes one there, unless its
  # type is a division's: Gorboduc's dumb shows and La Silvanira's inductions are
  # divisions of the text. A paratext whose kind is a division's type too (`prologo`,
  # `argumento`) says so, `ana="paratexto"`.
  defp paratext_div1?(type, attrs, children) do
    (attr_value(attrs, "ana") == "paratexto" or type not in Division.body_types()) and
      Enum.all?(children, &(not is_tuple(&1) or elem(&1, 0) in ~w(head p lg trailer)))
  end

  # The characters the file declares, each by its first role with that xml:id, in the
  # file's order: a list inside an act after the act.
  defp declared_characters(divisions) do
    divisions
    |> Enum.flat_map(&[&1 | &1.divisions])
    |> Enum.flat_map(&Map.get(&1, :characters, []))
    |> Enum.uniq_by(& &1.xml_id)
    |> Enum.with_index(fn character, position -> %{character | position: position} end)
  end

  # --- Back: the bibliography ---

  # Every biblStruct of a bibliography's listBibls, read into the entry it describes, as
  # Entry.description/1 gives it, with where the play sits in it (its citedRanges). A
  # bibliography in prose, as seven source files give theirs, has no listBibl: nothing.
  defp bibliography(nil), do: []

  defp bibliography({_name, _attrs, children}) do
    for {"div", attrs, parts} <- children,
        attr_value(attrs, "type") == "bibliografia",
        {"listBibl", list_attrs, structs} <- parts,
        {"biblStruct", _, _} = struct <- structs do
      reference(struct, Entry.kind_from_tei_list(attr_value(list_attrs, "type")))
    end
  end

  defp reference({_name, attrs, children}, kind) do
    analytic = children_of(find_child(children, "analytic"))
    monogr = children_of(find_child(children, "monogr"))
    imprint = children_of(find_child(monogr, "imprint"))
    series = children_of(find_child(children, "series"))

    entry = %Entry{
      kind: kind,
      pub_type: Entry.pub_type_from_tei(attr_value(attrs, "type")),
      language: attr_value(attrs, "xml:lang"),
      analytic_author: analytic |> find_children("author") |> people(),
      analytic_title: analytic |> typed("title", nil) |> running_text(),
      analytic_editors: analytic |> editors(nil) |> people(),
      analytic_translators: analytic |> editors("translator") |> people(),
      monogr_author: monogr |> find_children("author") |> people(),
      monogr_title: monogr |> typed("title", nil) |> running_text(),
      monogr_editors: monogr |> editors(nil) |> people(),
      monogr_translators: monogr |> editors("translator") |> people(),
      original_title: monogr |> typed("title", "original") |> running_text(),
      siglum: monogr |> typed("idno", "siglum") |> running_text(),
      edition: running_text(find_child(monogr, "edition")),
      volumes_total: monogr |> find_child("extent") |> running_text() |> volumes(),
      volume: monogr |> with_attr("biblScope", "unit", "volume") |> running_text(),
      issue: monogr |> with_attr("biblScope", "unit", "issue") |> running_text(),
      pages: monogr |> with_attr("biblScope", "unit", "page") |> running_text(),
      pub_place: running_text(find_child(imprint, "pubPlace")),
      publisher: running_text(find_child(imprint, "publisher")),
      year_text: imprint |> typed("date", nil) |> running_text(),
      url_accessed_on: imprint |> typed("date", "access") |> running_text(),
      series: running_text(find_child(series, "title")),
      public_note: running_text(find_child(children, "note")),
      url: children |> find_child("ptr") |> attrs_of() |> attr_value("target")
    }

    %{
      description: Entry.description(entry),
      volume: children |> with_attr("citedRange", "unit", "volume") |> running_text(),
      pages: children |> with_attr("citedRange", "unit", "page") |> running_text()
    }
  end

  # A bibliography field's text as it runs: italics as <<…>>, whitespace collapsed but none
  # added. text_content/1 joins an element's pieces with a space, which would put one
  # between "<<Adonis y Venus>>" and ": hacia", and a reference is matched on its words.
  defp running_text(nil), do: nil

  defp running_text(element),
    do: element |> run() |> String.replace(~r/\s+/u, " ") |> String.trim()

  defp run(text) when is_binary(text), do: text
  # A line break the export wrote for a curator's Enter: whitespace, as it was before.
  defp run({"lb", _attrs, _children}), do: " "

  # The italics keep their spaces: the export wrote them on one line, so a space inside
  # an <emph> is the curator's ("<<Foo >>bar"), not indentation.
  defp run({name, attrs, children}) do
    text = Enum.map_join(children, &run/1)
    if emph_element?(name, attrs), do: italics(text), else: text
  end

  defp run(_other), do: ""

  # One element per person in the file, one field in Playcode: joined with "; ", as FileMaker
  # keeps several people (Entry.people/1). Nil for none.
  defp people(elements) do
    case elements |> Enum.map(&running_text/1) |> Enum.reject(&(&1 == "")) do
      [] -> nil
      names -> Enum.join(names, "; ")
    end
  end

  # The <editor>s of a level whose @role is `role` (nil: an editor; "translator").
  defp editors(children, role),
    do:
      children
      |> find_children("editor")
      |> Enum.filter(&(attr_value(elem(&1, 1), "role") == role))

  # The export writes a total of volumes as "6 vols.".
  defp volumes(nil), do: nil
  defp volumes(text), do: String.replace_suffix(text, " vols.", "")

  defp children_of({_name, _attrs, children}), do: children
  defp children_of(nil), do: []

  defp attrs_of({_name, attrs, _children}), do: attrs
  defp attrs_of(nil), do: []

  # --- Paratexts ---

  # A paratext (dedication, editor's introduction, …), kept when it has a heading or
  # paragraphs: 12 head titles are a heading alone.
  defp paratext(type, children, pos) do
    heading = with "" <- safe_text(find_child(children, "head")), do: nil
    verse = find_child(children, "lg") != nil
    content = if verse, do: stanzas(children), else: paratext_paragraphs(children)

    if heading == nil and content == "" do
      []
    else
      [
        %{
          kind: kind(type),
          heading: heading,
          content: if(content != "", do: content),
          verse: verse,
          trailer: with("" <- safe_text(find_child(children, "trailer")), do: nil),
          position: pos
        }
      ]
    end
  end

  # Each <lb/> a line break; an empty line between two (before a signature, in 140
  # plays) is the blank line that parts paragraphs, so it reads as a new one.
  defp paratext_paragraphs(children) do
    children
    |> find_children("p")
    |> Enum.map_join("\n\n", &lines_text/1)
    |> String.split(~r/\n\s*\n/)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  # A paratext in verse (question 30): a line to a line, a blank line between stanzas.
  # ponytail: a div holding stanzas and paragraphs (no file has one) keeps its stanzas
  # only; read both in the file's order if one turns up.
  defp stanzas(children) do
    for {"lg", _, lines} <- children do
      for line <- find_children(lines, "l"), do: text_content(line)
    end
    |> Enum.map_join("\n\n", &Enum.join(&1, "\n"))
  end

  # The file's own word, kept as a stage direction's is. The scene of the action, which 45
  # files give as a div, is TEI's <set>; nota (0784's only) and a div with no type are a
  # note on the digital edition.
  defp kind("circunstancia_accion"), do: "lugar_accion"
  defp kind(type) when type in ~w(nota front), do: "nota_edicion_digital"
  defp kind(type), do: type

  # --- Cast list ---

  # A div (div1, div2) of type `elenco`: its heading, and the castList inside, if any.
  defp elenco(children, pos),
    do:
      cast_list(find_child(children, "head"), children_of(find_child(children, "castList")), pos)

  # A cast list: an `elenco` division holding its entries, one per castItem, those of a
  # castGroup under the group's head. An entry names the character it declares
  # (`xml:id`) or refers to (`corresp`), or none; a role with an xml:id also gives the
  # character.
  defp cast_list(head, list_children, pos) do
    items = Enum.flat_map(list_children, &cast_items/1)

    %{
      type: "elenco",
      number: nil,
      title: safe_text(head),
      position: pos,
      notes: [],
      elements: [],
      divisions: [],
      entries:
        items
        |> Enum.with_index()
        |> Enum.map(fn {{entry, _character}, position} -> %{entry | position: position} end),
      characters: for({_entry, character} <- items, character, do: character)
    }
  end

  defp cast_items({"castItem", attrs, children}), do: cast_item(attrs, children, nil)

  defp cast_items({"castGroup", _attrs, children}) do
    group = safe_text(find_child(children, "head"))
    for {"castItem", attrs, item} <- children, entry <- cast_item(attrs, item, group), do: entry
  end

  defp cast_items(_other), do: []

  defp cast_item(attrs, children, group) do
    case find_child(children, "role") do
      nil ->
        []

      {_role_name, role_attrs, _role_children} = role ->
        # Clean xml_id (some have newlines)
        xml_id =
          with id when is_binary(id) <-
                 attr_value(role_attrs, "xml:id") || attr_value(role_attrs, "id"),
               do: String.trim(id)

        corresp =
          with ref when is_binary(ref) <- attr_value(role_attrs, "corresp"),
               do: ref |> String.trim() |> String.trim_leading("#")

        # A role left empty (0714's Daphné) is named by its id, so its speeches keep it;
        # one with no id either names no one and prints nothing.
        name =
          case role |> text_content() |> String.trim() do
            "" -> xml_id || corresp
            text -> text
          end

        description = safe_text(find_child(children, "roleDesc"))

        character =
          if xml_id,
            do: %{
              xml_id: xml_id,
              name: name,
              description: description,
              actor: safe_text(find_child(children, "actor")),
              is_hidden: attr_value(attrs, "ana") == "oculto",
              position: 0
            }

        entry = %{
          name: name,
          description: description,
          group_heading: group,
          position: 0,
          character: xml_id || corresp
        }

        if name, do: [{entry, character}], else: []
    end
  end

  # --- Body (acts, scenes, speeches, etc.) ---

  defp act(type, attrs, act_children, pos) do
    {heading, notes} = text_and_notes(find_child(act_children, "head"))
    {elements, scenes} = act_children |> closing_scene_as_trailer() |> act_content()

    %{
      type: type,
      number: parse_int(attr_value(attrs, "n")),
      title: heading,
      position: pos,
      notes: notes,
      elements: elements,
      divisions: scenes
    }
  end

  # The words the corpus closes with: fin, fine, finis, il fine, telón (spaced out once).
  @closing_words ~r/\A\W*(?:il\s+)?fin(?:e|is)?\b|\A\W*t\s*e\s*l\s*[óo]\s*n\b/iu

  # An act whose last scene holds nothing but a heading of closing words ("FIN DE
  # CORIOLANO.", "Finis actus primi.", "T E L Ó N": 70 acts in 39 plays of the corpus)
  # ends with its trailer, encoded as a scene; the heading becomes that trailer.
  defp closing_scene_as_trailer(children) do
    with [{"div2", _, scene_children} | before] <-
           children |> Enum.reject(&is_binary/1) |> Enum.reverse(),
         [{"head", _, words} = head] <- Enum.reject(scene_children, &is_binary/1),
         true <- head |> text_content() |> String.match?(@closing_words) do
      Enum.reverse(before, [{"trailer", [], words}])
    else
      _ -> children
    end
  end

  # An act's own elements and its scenes. The act's elements and its scenes' share one
  # position counter: a scene's first element follows the last element before it. A cast
  # list in the act, a bare castList or a div2 of type `elenco`, stands among the scenes.
  defp act_content(children) do
    {_el_pos, _scene_pos, elements, scenes} =
      Enum.reduce(children, {0, 0, [], []}, fn
        {"castList", _attrs, list_children}, {el_pos, scene_pos, elements, scenes} ->
          list = cast_list(find_child(list_children, "head"), list_children, scene_pos)
          {el_pos, scene_pos + 1, elements, [list | scenes]}

        {"div2", attrs, div2_children}, {el_pos, scene_pos, elements, scenes} ->
          scene =
            if attr_value(attrs, "type") == "elenco",
              do: elenco(div2_children, scene_pos),
              else: scene(attrs, div2_children, el_pos, scene_pos)

          {el_pos + length(scene.elements), scene_pos + 1, elements, [scene | scenes]}

        child, {el_pos, scene_pos, elements, scenes} = acc ->
          case act_element(child, el_pos) do
            nil -> acc
            element -> {el_pos + 1, scene_pos, [element | elements], scenes}
          end
      end)

    {Enum.reverse(elements), Enum.reverse(scenes)}
  end

  defp scene(attrs, children, el_pos, scene_pos) do
    {heading, notes} = text_and_notes(find_child(children, "head"))

    %{
      type: (attr_value(attrs, "type") || "escena") |> String.downcase(),
      number: parse_int(attr_value(attrs, "n")),
      title: heading,
      position: scene_pos,
      notes: notes,
      elements: scene_content(children, el_pos),
      divisions: []
    }
  end

  # An element directly in an act; nil for anything else (the head is the act's title).
  defp act_element({"sp", attrs, children}, pos), do: speech(attrs, children, pos)
  defp act_element({"stage", _, _} = stage, pos), do: stage_direction(stage, pos)
  defp act_element({"p", _, _} = para, pos), do: prose(para, pos)
  defp act_element({"lg", attrs, children}, pos), do: line_group(attrs, children, pos)
  defp act_element({"trailer", _, _} = trailer, pos), do: trailer(trailer, pos)
  defp act_element({"opener", _, _} = opener, pos), do: opener(opener, pos)
  defp act_element(_other, _pos), do: nil

  # A scene's speeches, stage directions, trailer, and the paragraphs and stanzas nobody
  # speaks, numbered from `first`. Nothing else in a scene is read.
  defp scene_content(children, first) do
    children
    |> Enum.filter(&match?({name, _, _} when name in ~w(sp stage trailer p lg), &1))
    |> Enum.with_index(first)
    |> Enum.map(fn {child, pos} -> act_element(child, pos) end)
  end

  # --- Speech ---

  defp speech(attrs, children, pos) do
    speaker = find_child(children, "speaker")
    {label, notes} = text_and_notes(speaker)

    %{
      type: "speech",
      position: pos,
      speaker_label: with_folio_edges(label, speaker && elem(speaker, 1)),
      who: who(attr_value(attrs, "who")),
      notes: notes,
      elements: speech_content(children)
    }
  end

  # A speech's line groups, lines, stage directions and paragraphs.
  defp speech_content(children) do
    children
    |> Enum.filter(&match?({name, _, _} when name in ~w(lg l stage p), &1))
    |> Enum.with_index()
    |> Enum.map(fn
      {{"lg", attrs, lg_children}, pos} -> line_group(attrs, lg_children, pos)
      {{"l", _, _} = line, pos} -> verse_line(line, pos)
      {{"stage", _, _} = stage, pos} -> stage_direction(stage, pos)
      {{"p", _, _} = para, pos} -> prose(para, pos)
    end)
  end

  # who can be "#ALFONSO" (single) or "#ALB #COR" (multi-character, space-separated)
  defp who(nil), do: []

  defp who(who) do
    who
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map(&(&1 |> String.replace("#", "") |> String.trim()))
  end

  # --- Line group ---

  defp line_group(attrs, children, pos) do
    %{
      type: "line_group",
      position: pos,
      verse_type: attr_value(attrs, "type"),
      part: attr_value(attrs, "part"),
      notes: [],
      elements:
        children
        |> Enum.filter(&match?({name, _, _} when name in ~w(l stage), &1))
        |> Enum.with_index()
        |> Enum.map(fn
          {{"l", _, _} = line, line_pos} -> verse_line(line, line_pos)
          {stage, stage_pos} -> stage_direction(stage, stage_pos)
        end)
    }
  end

  # --- Verse line ---

  defp verse_line({_name, attrs, children} = line, pos) do
    is_aside = aside_delivery?(children)
    {content, notes} = line |> verse_line_content(is_aside) |> take_notes(line)

    %{
      type: "verse_line",
      position: pos,
      content: with_folio_edges(content, attrs),
      line_number: parse_int(attr_value(attrs, "n")),
      line_id: attr_value(attrs, "xml:id") || attr_value(attrs, "id"),
      part: attr_value(attrs, "part"),
      rend: attr_value(attrs, "rend"),
      is_aside: is_aside,
      notes: notes,
      elements: []
    }
  end

  # Returns true if the children of an <l> element indicate an aside, either via:
  # - <stage type="delivery">[Aparte.]</stage>
  # - <seg type="aside">...</seg>
  defp aside_delivery?(children) when is_list(children) do
    Enum.any?(children, fn
      {"stage", attrs, stage_children} ->
        stage_type(attrs) == "delivery" and
          String.match?(
            text_content({"stage", attrs, stage_children}),
            ~r/aparte/i
          )

      {"seg", attrs, _} ->
        attr_value(attrs, "type") == "aside"

      _ ->
        false
    end)
  end

  defp aside_delivery?(_), do: false

  # The spoken text of a verse line, read with note marks (text_content/2). An aside line
  # is aside_text/1; with no <seg>, the line without its delivery <stage>, its entries kept.
  defp verse_line_content({_name, _attrs, children} = line, true) do
    if aside_in_children?(children) do
      aside_text(line)
    else
      children
      |> without_stages()
      |> pieces(:mark, &text_content(&1, :mark))
      |> squeeze()
    end
  end

  defp verse_line_content(line, false), do: text_content(line, :mark)

  defp aside_seg?({"seg", attrs, _}), do: attr_value(attrs, "type") == "aside"
  defp aside_seg?(_), do: false

  # --- Stage direction, trailer, prose ---

  defp stage_direction({_name, attrs, _children} = stage, pos) do
    {content, notes} = text_and_notes(stage)

    %{
      type: "stage_direction",
      position: pos,
      content: with_folio_edges(content, attrs),
      stage_type: stage_type(attrs),
      notes: notes,
      elements: []
    }
  end

  defp trailer(trailer, pos) do
    {content, notes} = text_and_notes(trailer)
    %{type: "trailer", position: pos, content: content, notes: notes, elements: []}
  end

  # The opening formula: its salute, the only part of an opener the corpus writes.
  defp opener({_name, _attrs, children}, pos) do
    {content, notes} = text_and_notes(find_child(children, "salute"))
    %{type: "opener", position: pos, content: content, notes: notes, elements: []}
  end

  defp prose({_name, attrs, children} = para, pos) do
    is_aside = aside_in_children?(children)
    marked = if is_aside, do: aside_text(para), else: text_content(para, :mark)
    {content, notes} = take_notes(marked, para)
    content = with_folio_edges(content, attrs)
    # p@n: the number of the paragraph's first printed line, a marker at its very start.
    content =
      if content == "", do: content, else: printed_line(attr_value(attrs, "n")) <> content

    %{
      type: "prose",
      position: pos,
      content: content,
      is_aside: is_aside,
      notes: notes,
      elements: []
    }
  end

  # Check if children contain a <seg type="aside"> element
  defp aside_in_children?(children) when is_list(children), do: Enum.any?(children, &aside_seg?/1)

  defp aside_in_children?(_), do: false

  # A line or paragraph holding a <seg type="aside">. All aside, when every word is in a
  # seg: the segs' text, with the element's own notes and breaks, its stages dropped (the
  # delivery, "(Aparte)", is what is_aside says) but their entries kept (without_stages/1). Partly aside: the whole text, each seg an
  # <aside> marker (read_child/3).
  defp aside_text({_name, _attrs, children} = element) do
    if Enum.any?(children, &spoken_outside_aside?/1),
      do: text_content(element, :mark),
      else: aside_content(children)
  end

  defp spoken_outside_aside?(text) when is_binary(text), do: String.trim(text) != ""

  defp spoken_outside_aside?({name, _, _} = child),
    do: name not in ~w(stage note app) and not aside_seg?(child) and text_content(child) != ""

  defp spoken_outside_aside?(_), do: false

  defp aside_content(children) do
    children
    |> without_stages()
    |> Enum.filter(&(aside_seg?(&1) or match?({name, _, _} when name in ~w(note app lb), &1)))
    |> pieces(:mark, fn
      {"lb", attrs, _} -> line_break(attrs)
      seg -> text_content(seg, :mark)
    end)
    |> squeeze()
  end

  # --- XML helpers ---

  defp find_child(children, name) when is_list(children) do
    Enum.find(children, fn
      {^name, _, _} -> true
      _ -> false
    end)
  end

  defp find_child(_, _), do: nil

  defp find_children(children, name) when is_list(children) do
    Enum.filter(children, fn
      {^name, _, _} -> true
      _ -> false
    end)
  end

  defp find_children(_, _), do: []

  # The text of an element, whitespace collapsed, italics as <<…>>. A <note> inside it is
  # pasted in (:paste, what the header and the front matter read) or left as a mark
  # (:mark, the play text), which take_notes/2 turns into the note's offset. :breaks reads
  # as :paste, but keeps each <lb/> as a break (a note's body).
  defp text_content(element, notes \\ :paste)

  defp text_content({name, attrs, children}, notes) do
    if emph_element?(name, attrs) do
      children |> extract_plain_text(notes) |> italics()
    else
      children |> pieces(notes, &read_child(&1, notes, name)) |> squeeze()
    end
  end

  defp text_content(text, _notes) when is_binary(text), do: String.trim(text)
  defp text_content(_, _notes), do: ""

  # An emphasis of nothing (EMOTHE0187's `<emph></emph>, if`) is no italics: kept as
  # "<<>>", it came back from the export as a stray space, a different file each time.
  defp italics(text), do: if(String.trim(text) == "", do: text, else: "<<" <> text <> ">>")

  @stage_parents ~w(l p seg)
  @leading_marks ~r/\A((?:\x{E000}\d+[sn]\x{E001} ?)*)(.*)\z/su

  # A child of the element `parent` being read. Under :mark (the play text) a <stage>
  # child of an <l>, <p> or <seg> is kept as a marker (InlineMarkup). Anywhere else (a
  # speaker label, a heading, a stage inside a standalone stage direction) its words are
  # pasted as text of the parent: TEI allows no <stage> there, and markers do not nest.
  defp read_child({"stage", attrs, _children} = stage, :mark, parent)
       when parent in @stage_parents,
       do: marker(stage, stage_tag(attrs), "</stage>")

  # A <seg type="aside"> of a line or paragraph partly aside (aside_text/1), likewise.
  defp read_child({"seg", _attrs, _children} = seg, :mark, parent) when parent in ~w(l p) do
    if aside_seg?(seg), do: marker(seg, "<aside>", "</aside>"), else: text_content(seg, :mark)
  end

  # A line break in the play text (:mark) or a note's body (:breaks); elsewhere, a space.
  defp read_child({"lb", attrs, _children}, notes, _parent) when notes in [:mark, :breaks],
    do: line_break(attrs)

  defp read_child(child, notes, _parent), do: text_content(child, notes)

  # `element` read as a marker opened by `open`. A note at its very start goes in front of
  # the tag, and a marker left with no words is dropped, its notes staying in the line.
  # The note leads with a space ("s") because the pieces of the element are joined by
  # one: the offset the first import stores is the one a re-import of the export
  # computes, a note before the marker.
  defp marker(element, open, close) do
    [_all, lead, words] = Regex.run(@leading_marks, text_content(element, :mark))
    lead = Regex.replace(~r/\A(\x{E000}\d+)[sn]/u, String.trim(lead), "\\1s")

    case String.trim(words) do
      "" -> lead
      words -> lead <> wrap(words, open, close)
    end
  end

  defp wrap(words, "<stage" <> _ = open, close), do: cut_around_folios(words, open, close)
  defp wrap(words, open, close), do: open <> words <> close

  # A passage may hold a stage but a stage may not hold a passage (InlineMarkup), so a
  # passage read inside a stage cuts it: the words before it, the passage's words and the
  # words after it are a stage each, the passage around its own, the same type again. A
  # space beside a piece stays where the file put it, outside the tags.
  defp cut_around_folios(words, open, close) do
    ~r{<folio>.*?</folio>}su
    |> Regex.split(words, include_captures: true)
    |> Enum.map_join(fn
      "<folio>" <> rest ->
        "<folio>" <>
          in_stage(String.replace_suffix(rest, "</folio>", ""), open, close) <> "</folio>"

      piece ->
        in_stage(piece, open, close)
    end)
  end

  defp in_stage(piece, open, close) do
    case String.trim(piece) do
      "" -> piece
      words -> String.replace(piece, words, open <> words <> close, global: false)
    end
  end

  # Where an <lb/> stood while the pieces of a text are joined and squeezed: a character
  # squeeze/1 does not take for whitespace, so the file's own line ends, which are, still
  # collapse. take_notes/2 and parse_note/2 turn it into the \n the text keeps.
  @break "\u{E002}"

  # An <lb/>: a break, or, with a number, where a printed line of the source starts. A
  # number the marker cannot hold is read as before, a space.
  defp line_break(attrs) do
    case attr_value(attrs, "n") do
      nil -> @break
      n -> printed_line(n)
    end
  end

  # The marker for printed line `n`, or nothing when `n` is absent or not a number the
  # marker can hold.
  defp printed_line(nil), do: ""

  defp printed_line(n),
    do: if(n =~ ~r/\A[A-Za-z0-9.\-]+\z/, do: InlineMarkup.number_marker(n), else: "")

  # The type goes into the marker when it is the plain word the marker allows.
  defp stage_tag(attrs) do
    type = stage_type(attrs)

    if type && type =~ ~r/\A[A-Za-z0-9_]+\z/, do: ~s(<stage type="#{type}">), else: "<stage>"
  end

  # A <stage>'s @type. 24 source files spell TEI's "delivery" "delivery_".
  defp stage_type(attrs) do
    case attr_value(attrs, "type") do
      "delivery_" -> "delivery"
      type -> type
    end
  end

  # A <note>'s @type. Two are slips (question 17): La tragedia española's note on "Belona",
  # typed "video", is a translator's, and Marta la piadosa's "nota_editor_digital" a
  # digital editor's.
  defp note_type(attrs) do
    case attr_value(attrs, "type") do
      "video" -> "traductor"
      "nota_editor_digital" -> "editor_digital"
      type -> type
    end
  end

  defp emph_element?("emph", _attrs), do: true

  defp emph_element?("hi", attrs),
    do: attr_value(attrs, "rend") in ["italic", "italics"]

  defp emph_element?(_, _), do: false

  defp extract_plain_text(children, notes) when is_list(children),
    do: children |> pieces(notes, &emph_child(&1, notes)) |> squeeze()

  defp emph_child({"lb", attrs, _}, notes) when notes in [:mark, :breaks], do: line_break(attrs)
  defp emph_child({_name, _attrs, children}, notes), do: extract_plain_text(children, notes)

  # Pieces of text as one string, a space between them, whitespace collapsed. A break
  # takes the place of the spaces around it; a number keeps the space before it and none
  # after, as the text read before it was kept had them.
  defp squeeze(pieces) do
    pieces
    |> join_pieces()
    |> String.replace(~r/\s+/, " ")
    |> String.replace(~r/ ?\x{E002} ?/u, @break)
    |> String.replace(~r/(<lb n="[^"]*"\/>) /, "\\1")
    |> String.trim()
  end

  @folio_tag_first ~r/\A\s*<\/?folio(?: part="[IMF]")?>/
  @folio_tag_last ~r/<\/?folio(?: part="[IMF]")?>\s*\z/

  # A text trimmed, but for the white space beside a Folio tag at its edge: it is the
  # file's own, and join_pieces/1 adds none there.
  defp trim_beside_folio(text) do
    words = String.trim(text)

    if String.contains?(words, "folio") do
      [lead, trail] = String.split(text, words, parts: 2)
      lead = if text =~ @folio_tag_first, do: lead, else: ""
      trail = if text =~ @folio_tag_last, do: trail, else: ""
      lead <> words <> trail
    else
      words
    end
  end

  # An element's piece with the space that parts it from its neighbours, which a Folio tag
  # at its edge (a stage that is all passage) would lose to join_pieces/1.
  defp space_beside_folio(piece) do
    piece = if piece =~ @folio_tag_first, do: " " <> piece, else: piece
    if piece =~ @folio_tag_last, do: piece <> " ", else: piece
  end

  # The pieces of a text as one string, a space between them, but none where the file
  # glues an italic to its neighbour (`pieces/3`: "un <emph>sueño</emph>, fue" reads
  # "sueño,", not "sueño ,"), and none beside a Folio tag at a piece's edge, where the white
  # space is the file's own (trim_beside_folio/1): a passage whose reading starts or ends
  # with an element gains no space around it.
  defp join_pieces(pieces) do
    pieces
    |> Enum.chunk_every(2, 1)
    |> Enum.map_join(fn
      [{piece, glued?}, {next, _}] ->
        if glued? or piece =~ @folio_tag_last or next =~ @folio_tag_first,
          do: piece,
          else: piece <> " "

      [{piece, _glued?}] ->
        piece
    end)
  end

  # What leaves the play text and is stored at its offset: a note, and an entry of the
  # critical apparatus.
  @apart ~w(note app)

  # `children` with each <stage> replaced by its own entries, where the stage stood: a line
  # that drops its stages (the delivery, "(Aparte)", is what is_aside says) keeps their
  # entries. A note inside the stage goes with it, and so does an entry that note copies.
  defp without_stages(children) do
    Enum.flat_map(children, fn
      {"stage", _, _} = stage -> for {"app", _, _} = app <- outermost(stage, @apart), do: app
      child -> [child]
    end)
  end

  # Each child's text, read by `fun`. Under :mark (the play text) a <note> or <app> child is
  # its mark instead; elsewhere (a note's own text) an <app> is left out, its neighbours
  # joined as written: a note that copies its line's entry keeps the line's words.
  defp pieces(children, notes, fun) do
    children = if notes == :mark, do: children, else: without(children, "app")

    children
    |> Enum.zip(Enum.drop(children, 1) ++ [nil])
    |> Enum.with_index()
    |> Enum.map(fn {{child, next}, i} ->
      piece =
        case child do
          {name, _, _} when notes == :mark and name in @apart -> note_mark(child, children, i)
          text when is_binary(text) -> trim_beside_folio(text)
          child when is_tuple(child) -> child |> fun.() |> space_beside_folio()
          _ -> ""
        end

      {piece, glued?(child, next)}
    end)
  end

  # Whether the file writes `child` and `next` with no white space between them where one
  # is an italic and the other a word or an italic (italics are formatting), or where an
  # element is followed by closing punctuation ("(ti priego), dimmi"): no space is added
  # there. Otherwise an element (a stage, an aside, a printed line's number) is set apart
  # from its neighbours whatever the spacing.
  defp glued?(_child, nil), do: false

  defp glued?(child, next) do
    (italic_beside_word?(child, next) or (is_tuple(child) and closing_punctuation?(next))) and
      not space_at?(child, :trail) and not space_at?(next, :lead)
  end

  defp italic_beside_word?(child, next),
    do: (italic?(child) and word_or_italic?(next)) or (italic?(next) and word_or_italic?(child))

  defp closing_punctuation?(text) when is_binary(text), do: text =~ ~r/\A[,.;:!?)\]»…]/u
  defp closing_punctuation?(_node), do: false

  defp word_or_italic?(node), do: is_binary(node) or italic?(node)

  defp italic?({name, attrs, _children}), do: emph_element?(name, attrs)
  defp italic?(_text), do: false

  # Whether `node`'s text starts (`:lead`) or ends (`:trail`) with white space, an
  # element's own text, its notes and entries of the apparatus left out.
  defp space_at?(text, :lead) when is_binary(text), do: text =~ ~r/\A\s/u
  defp space_at?(text, :trail) when is_binary(text), do: text =~ ~r/\s\z/u

  defp space_at?({_name, _attrs, children}, side) do
    children = Enum.reject(children, &match?({name, _, _} when name in @apart, &1))

    case if(side == :lead, do: List.first(children), else: List.last(children)) do
      nil -> false
      node -> space_at?(node, side)
    end
  end

  # Where a note was in the text being read: "\u{E000}<key><s|n>\u{E001}". The key finds
  # the note again among the element's (take_notes/2); "s" records that the source had
  # whitespace beside the note, so the words either side stay apart, and "n" that it had
  # none, so "Iliria<note/>." reads "Iliria.".
  defp note_mark(note, siblings, i) do
    before = if i > 0, do: Enum.at(siblings, i - 1)
    next = Enum.at(siblings, i + 1)

    spaced =
      (is_binary(before) and before =~ ~r/\s\z/u) or (is_binary(next) and next =~ ~r/\A\s/u)

    "\u{E000}#{:erlang.phash2(note)}#{if spaced, do: "s", else: "n"}\u{E001}"
  end

  @note_mark ~r/ ?\x{E000}(\d+)([sn])\x{E001} ?/u

  # Takes the note marks out of `marked`, text `element` was read into with :mark.
  # Returns the text and its notes (parse_note/2), each offset counting graphemes of the text
  # without its << and >> markers and stage tags, as InlineMarkup.plain/1 does. A note
  # whose mark the reading dropped (inside a stripped aside <stage>) is dropped with it.
  # So is a note with no text. An entry inside a note that copies none of the element's
  # comes out after the note (strays/2).
  # ponytail: two adjacent notes each with whitespace beside them ("a <note/><note/> b")
  # store "a  b" and the second note one grapheme later; the corpus has no note after a
  # space. Carry a pending space to the next text if one turns up.
  defp take_notes(marked, element) do
    by_key = Map.new(outermost(element, @apart), &{Integer.to_string(:erlang.phash2(&1)), &1})

    own =
      for {"app", attrs, _} <- outermost(element, @apart),
          into: MapSet.new(),
          do: attr_value(attrs, "n")

    {text, found} =
      @note_mark
      |> Regex.split(marked, include_captures: true)
      |> Enum.reduce({"", []}, fn piece, {text, found} ->
        case Regex.run(@note_mark, piece) do
          [_, key, spaced] ->
            space =
              if spaced == "s" and text != "" and not String.ends_with?(text, @break),
                do: " ",
                else: ""

            {text <> space, [{plain_length(text), Map.fetch!(by_key, key)} | found]}

          nil ->
            {text <> piece, found}
        end
      end)

    text = text |> String.trim_trailing() |> String.replace(@break, "\n")
    last = plain_length(text)

    {text,
     found
     |> Enum.reverse()
     |> Enum.flat_map(fn {offset, note} ->
       offset = min(offset, last)
       parse_note(note, offset) ++ Enum.flat_map(strays(note, own), &parse_note(&1, offset))
     end)}
  end

  # The <app>s inside a note that copy none of its element's entries (`own`, their `n`s):
  # EMOTHE0530's n="496", only in the note on "ne". They move into the line, after the
  # note; the others are copies of the line's entry, which the note's text leaves out.
  defp strays({"note", _, _} = note, own),
    do: note |> outermost(["app"]) |> Enum.reject(&(attr_value(elem(&1, 1), "n") in own))

  defp strays(_app, _own), do: []

  @inline_marker ~r/<<|>>|<stage(?: type="[A-Za-z0-9_]+")?>|<\/stage>|<\/?aside>|<folio(?: part="[IMF]")?>|<\/folio>|<lb n="[A-Za-z0-9.\-]+"\/>/

  # Graphemes of `text` without its markers, one marker at a time: a note inside an
  # italic run or a stage is read while the run is still open, so InlineMarkup.plain/1,
  # which needs the closing marker, cannot do it.
  defp plain_length(text), do: text |> String.replace(@inline_marker, "") |> String.length()

  # The elements named `names` inside `element`, not counting those inside them: a line's
  # notes and entries, not a note's own entries or an entry's readings' notes.
  defp outermost({_name, _attrs, children}, names) do
    Enum.flat_map(children, fn
      {name, _, _} = child -> if name in names, do: [child], else: outermost(child, names)
      _text -> []
    end)
  end

  # An element of the play text read with its notes taken out: `{text, [note]}`, or
  # `{nil, []}` for no element.
  defp text_and_notes(nil), do: {nil, []}
  defp text_and_notes(element), do: element |> text_content(:mark) |> take_notes(element)

  # A note's fields at `offset`, as a list: empty when the note has no text, since there is
  # nothing to show (the empty notes of the EMOTHE0010 test file).
  defp parse_note({"note", attrs, children} = note, offset) do
    case note_text(note) do
      nil ->
        []

      body ->
        term = safe_text(find_child(children, "term"))

        [
          %{
            offset: offset,
            n: attr_value(attrs, "n"),
            type: note_type(attrs),
            term: if(term in [nil, ""], do: nil, else: term),
            body: body
          }
        ]
    end
  end

  # An entry of the critical apparatus: a variant (Note.variant/0) at `offset`, its readings
  # in order, each without its own note, which is the reading's; the entry's own note is its
  # body. An empty entry is kept: Hamlet's damaged ones are written back as they are.
  defp parse_note({"app", attrs, children}, offset) do
    [
      %{
        offset: offset,
        n: attr_value(attrs, "n"),
        type: Note.variant(),
        variant_type: attr_value(attrs, "type"),
        range_end: attr_value(attrs, "to"),
        body: note_text(find_child(children, "note")),
        readings:
          for {name, reading_attrs, reading_children} <- children, name in ~w(lem rdg) do
            %{
              lemma: name == "lem",
              wit: attr_value(reading_attrs, "wit"),
              text: text_content({name, reading_attrs, without(reading_children, "note")}),
              note: note_text(find_child(reading_children, "note"))
            }
          end
      }
    ]
  end

  # A note's text: its paragraphs, a blank line between them, its <term> left out; nil for
  # no note, or one with no text (a note of nothing but breaks, EMOTHE0299's <p><lb/></p>).
  defp note_text(nil), do: nil

  defp note_text({"note", attrs, children}) do
    body =
      case find_children(children, "p") do
        [] ->
          text_content(
            {"note", attrs, Enum.reject(children, &match?({"term", _, _}, &1))},
            :breaks
          )

        paragraphs ->
          paragraphs
          |> Enum.map(&text_content(&1, :breaks))
          |> Enum.reject(&(&1 == ""))
          |> Enum.join("\n\n")
      end
      |> String.replace(@break, "\n")

    if String.trim(body) == "", do: nil, else: body
  end

  # `children` without the `name` elements, the text either side joined as written: "is" and
  # "»" around an <app> read "is»", not "is »".
  defp without(children, name) do
    children
    |> Enum.reject(&match?({^name, _, _}, &1))
    |> Enum.chunk_by(&is_binary/1)
    |> Enum.flat_map(fn
      [text | _] = texts when is_binary(text) -> [Enum.join(texts)]
      elements -> elements
    end)
  end

  defp safe_text(nil), do: nil
  defp safe_text(element) when is_tuple(element), do: text_content(element)
  defp safe_text(text) when is_binary(text), do: String.trim(text)

  # --- Performances (S5) ---

  # A `<performance>` of the front as the export writes it: its <p> has the date (its years
  # the attributes, as a composition date's), the venue and its type, the town with the
  # state it belonged to (as a setting's), the company; then the cast list, the note and the
  # source, a biblStruct the bibliography's own reader reads. Its actors are the play's cast
  # list's when its `corresp` is the id the export gives that list.
  defp performance(attrs, children) do
    details = children_of(find_child(children, "p"))
    date = find_child(details, "date")
    venue = typed(details, "rs", "venue")
    place = find_child(details, "placeName")
    {year_from, year_to} = creation_years(attrs_of(date))
    {source, volume, pages} = performance_source(find_child(children, "biblStruct"))

    %{
      date_text: line_text(date),
      year_from: year_from,
      year_to: year_to,
      venue: line_text(venue),
      venue_type: venue_type(venue),
      place: place_slug(place),
      state: setting_state(children_of(place)),
      company: details |> find_child("orgName") |> line_text(),
      note: note_text(find_child(children, "note")),
      cast: performance_cast(find_child(children, "castList")),
      source: source,
      source_volume: volume,
      source_pages: pages,
      cast_from_cast_list: attr_value(attrs, "corresp") == "#castlist"
    }
  end

  # A text of a performance: the words as `text_content/2` reads them, italics as <<…>>
  # and each <lb/> a line break, squeezed as a form's text is (`Text.squeeze/1`); nil for
  # none, a bare <lb/> included.
  defp line_text(nil), do: nil

  defp line_text(element),
    do: element |> text_content(:breaks) |> String.replace(@break, "\n") |> Text.squeeze()

  # The slug a <placeName> refers to; nil for none, as a state with no town has.
  defp place_slug(place) do
    case ref_slug(attrs_of(place)) do
      "" -> nil
      slug -> slug
    end
  end

  # The venue's type, when it is one of the eight.
  defp venue_type(venue) do
    type = attr_value(attrs_of(venue), "subtype")
    if type in Performance.venue_types(), do: type
  end

  defp performance_cast(nil), do: []

  defp performance_cast({_name, _attrs, children}) do
    for {"castItem", _attrs, item} <- children do
      actor = find_child(item, "actor")
      name = children_of(find_child(children_of(actor), "persName"))

      %{
        role: line_text(find_child(item, "role")),
        surname: line_text(find_child(name, "surname")),
        forename: line_text(find_child(name, "forename")),
        nickname: name |> typed("addName", "nickname") |> line_text(),
        sex: actor_sex(attr_value(attrs_of(actor), "sex"))
      }
    end
  end

  @actor_sex %{"M" => "man", "F" => "woman"}

  defp actor_sex(nil), do: nil
  defp actor_sex(sex), do: @actor_sex[String.upcase(String.trim(sex))]

  # The source: the reference it describes and where the performance sits in it. Its kind is
  # the file's `ana`; a file that names none cites a criticism, the kind most sources are.
  defp performance_source(nil), do: {nil, nil, nil}

  defp performance_source({_name, attrs, _children} = struct) do
    kind = Entry.kind_from_tei_source(attr_value(attrs, "ana")) || "criticism"
    %{description: description, volume: volume, pages: pages} = reference(struct, kind)

    {description, volume, pages}
  end

  defp attr_value(attrs, key) when is_list(attrs) do
    case List.keyfind(attrs, key, 0) do
      {^key, value} -> value
      nil -> nil
    end
  end

  defp attr_value(_, _), do: nil

  defp has_attr?(attrs, key), do: attr_value(attrs, key) != nil

  defp parse_int(nil), do: nil

  defp parse_int(str) do
    case Integer.parse(str) do
      {num, _} -> num
      :error -> nil
    end
  end

  defp clean_code(code) do
    code
    |> String.trim()
    |> String.replace(~r/[^a-zA-Z0-9_]/, "")
  end

  defp normalize_imported_title(nil), do: nil

  defp normalize_imported_title(title) when is_binary(title) do
    normalized_title = String.trim(title)

    if all_caps_text?(normalized_title) do
      normalized_title
      |> then(&Regex.split(~r/(\s+)/u, &1, include_captures: true))
      |> Enum.reduce({[], true}, fn segment, {acc, first_word?} ->
        if Regex.match?(~r/^\s+$/u, segment) do
          {[segment | acc], first_word?}
        else
          formatted_segment = format_title_segment(segment, first_word?)
          {[formatted_segment | acc], false}
        end
      end)
      |> elem(0)
      |> Enum.reverse()
      |> Enum.join()
    else
      normalized_title
    end
  end

  # A sort title in capitals is the title from some word on, its article put last
  # ("DISCRETA ENAMORADA LA"). Each word takes the case of the title's next word that
  # matches it, read round the title from the last match, so the article keeps its
  # capital ("Cid Le") and a word repeated mid-title its small letter ("Fuerza de la
  # Sangre La"); a word the title lacks ("COMEDIA FAMOSA DE") is title-cased on its own.
  defp normalize_sort_title(nil, _title), do: nil

  defp normalize_sort_title(sort_title, title) do
    if all_caps_text?(sort_title) do
      words = ~r/[\p{L}\p{N}'’\-]+/u |> Regex.scan(title || "") |> List.flatten()
      round = words ++ words

      sort_title
      |> String.split()
      |> Enum.map_reduce(0, fn word, from ->
        case Enum.find_index(Enum.drop(round, from), &(String.upcase(&1) == word)) do
          nil -> {format_title_segment(word, false), from}
          index -> {Enum.at(round, from + index), from + index + 1}
        end
      end)
      |> elem(0)
      |> Enum.join(" ")
    else
      sort_title
    end
  end

  defp all_caps_text?(text) do
    String.match?(text, ~r/\p{L}/u) && text == String.upcase(text) &&
      text != String.downcase(text)
  end

  defp format_title_segment(segment, first_word?) do
    case Regex.run(~r/^([^\p{L}\p{N}]*)([\p{L}\p{N}'’\-]+)([^\p{L}\p{N}]*)$/u, segment) do
      [_, leading, core, trailing] ->
        downcased_core = String.downcase(core)

        formatted_core =
          cond do
            Regex.match?(~r/^[ivxlcdm]+$/iu, core) ->
              String.upcase(core)

            not first_word? and MapSet.member?(@title_small_words, downcased_core) ->
              downcased_core

            true ->
              String.capitalize(downcased_core)
          end

        leading <> formatted_core <> trailing

      _ ->
        segment
    end
  end
end
