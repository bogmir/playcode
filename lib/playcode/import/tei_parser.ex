defmodule Playcode.Import.TeiParser do
  @moduledoc """
  Parses TEI-XML files into database records.

  Handles UTF-16 encoded files (common in the EMOTHE corpus) by converting
  them to UTF-8 before parsing with Saxy.
  """

  import Ecto.Query

  alias Playcode.Repo
  alias Playcode.Catalogue
  alias Playcode.Catalogue.{Play, PlayEditor, PlaySource, PlayEditorialNote}
  alias Playcode.PlayContent
  alias Playcode.PlayContent.{Character, Division, Element}
  alias Playcode.Places

  require Logger

  # Columns the platform owns, not the TEI file. `language` in particular: every EMOTHE
  # file carries xml:lang="es" for the editorial platform, so a re-import would undo the
  # FileMaker sync (docs/superpowers/plans/2026-08-01-s1-work-families-and-language.md).
  # New research columns added by later slices belong on this list.
  @platform_owned [
    :language,
    :relationship_type,
    :parent_play_id,
    :is_complete,
    :historical_time,
    :historical_time_note,
    :composition_date_from,
    :composition_date_to,
    :composition_date_note,
    :form
  ]

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
  Imports a TEI-XML file from the given path into the database.
  Returns {:ok, play} or {:error, reason}.
  """
  def import_file(path) do
    Logger.info("Importing TEI file: #{path}")

    case read_tree(path) do
      {:ok, tree} ->
        Repo.transaction(fn -> import_tree(tree) end)

      {:error, reason} ->
        Logger.error("Import failed for #{path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Reports what importing `path` would do, without writing anything.

  A re-import replaces the play's whole text and the editors, sources and notes the
  importer created itself; everything a researcher typed is kept, as are the columns
  the platform owns. This is what the admin import page and `--dry-run` print so that
  nobody discovers the replacement afterwards.
  """
  def preview_import(path) do
    with {:ok, {_name, _attrs, children}} <- read_tree(path),
         header when not is_nil(header) <- find_child(children, "teiHeader") do
      {:ok, preview_for(header)}
    else
      nil -> {:error, :missing_tei_header}
      {:error, reason} -> {:error, reason}
    end
  end

  defp preview_for({_name, _attrs, children}) do
    attrs =
      extract_play_attrs(
        find_child(children, "fileDesc"),
        find_child(children, "encodingDesc"),
        find_child(children, "profileDesc")
      )

    existing = Repo.get_by(Play, code: attrs.code)

    %{
      code: attrs.code,
      title: attrs.title,
      existing: existing,
      archived: not is_nil(existing) and not is_nil(existing.deleted_at),
      replaces: replaced_counts(existing),
      preserves: preserved_counts(existing),
      preserves_fields: preserved_fields(existing)
    }
  end

  @doc """
  Sums the mixed-ownership counts in one half of a `preview_import/1` result.

  Those four tables — editors, sources, notes and places — hold both TEI-imported and
  hand-entered rows, so `:replaces` and `:preserves` split each one by `origin`. Both
  the admin import page and the `--dry-run` output report the totals, and adding a
  fifth such table must not mean remembering two more addition sites.
  """
  def mixed_ownership_total(counts) do
    [:editors, :sources, :notes, :places] |> Enum.map(&Map.fetch!(counts, &1)) |> Enum.sum()
  end

  defp replaced_counts(nil),
    do: %{divisions: 0, elements: 0, characters: 0, editors: 0, sources: 0, notes: 0, places: 0}

  defp replaced_counts(%Play{id: id}) do
    %{
      divisions: count_rows(Division, id),
      elements: count_rows(Element, id),
      characters: count_rows(Character, id),
      editors: count_rows(PlayEditor, id, "tei"),
      sources: count_rows(PlaySource, id, "tei"),
      notes: count_rows(PlayEditorialNote, id, "tei"),
      places: count_rows(Places.PlayPlace, id, "tei")
    }
  end

  defp preserved_counts(nil), do: %{editors: 0, sources: 0, notes: 0, places: 0}

  defp preserved_counts(%Play{id: id}) do
    %{
      editors: count_rows(PlayEditor, id) - count_rows(PlayEditor, id, "tei"),
      sources: count_rows(PlaySource, id) - count_rows(PlaySource, id, "tei"),
      notes: count_rows(PlayEditorialNote, id) - count_rows(PlayEditorialNote, id, "tei"),
      places: count_rows(Places.PlayPlace, id) - count_rows(Places.PlayPlace, id, "tei")
    }
  end

  defp preserved_fields(nil), do: []

  defp preserved_fields(%Play{} = play) do
    Enum.filter(@platform_owned, fn field -> Map.get(play, field) not in [nil, false] end)
  end

  defp count_rows(schema, play_id) do
    Repo.aggregate(from(r in schema, where: r.play_id == ^play_id), :count, :id)
  end

  defp count_rows(schema, play_id, origin) do
    Repo.aggregate(
      from(r in schema, where: r.play_id == ^play_id and r.origin == ^origin),
      :count,
      :id
    )
  end

  defp read_tree(path) do
    with {:ok, raw} <- File.read(path),
         xml when is_binary(xml) <- normalize_encoding(raw),
         {:ok, tree} <- parse_xml(xml) do
      {:ok, tree}
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

  # --- Import Logic ---

  defp import_tree({_name, _attrs, children} = _tei) do
    header = find_child(children, "teiHeader")
    text = find_child(children, "text")

    if is_nil(header) do
      Repo.rollback(:missing_tei_header)
    end

    play = import_header(header)

    if text do
      import_text(text, play)
    end

    # Recompute verse_count from actual verse_line elements (the TEI header
    # <extent> value is often inaccurate or includes non-verse lines), and return
    # the play as that left it rather than the stale struct from before.
    {:ok, play} = Playcode.Catalogue.update_verse_count(play.id)
    play
  end

  # --- Header ---

  # A re-import replaces the text wholesale, but only the editors, sources and notes the
  # importer created itself. Anything a researcher typed — and every table later slices
  # add — stays. Deleting elements first lets the element_characters FK cascade handle
  # the join rows.
  defp reset_tei_content(%Play{id: id}) do
    for schema <- [Element, Division, Character] do
      Repo.delete_all(from(r in schema, where: r.play_id == ^id))
    end

    for schema <- [PlayEditor, PlaySource, PlayEditorialNote] do
      Repo.delete_all(from(r in schema, where: r.play_id == ^id and r.origin == "tei"))
    end

    # Only the links, never the places: the gazetteer is corpus-global authority data,
    # and an orphaned place shows in the admin list with a play count of 0.
    Places.delete_tei_play_places(id)
  end

  # Every editor, source and note the importer creates is stamped `origin: "tei"`, so a
  # re-import can replace its own rows and leave hand-entered ones alone. Rows created
  # anywhere else default to "manual".
  defp create_editor(attrs), do: Catalogue.create_play_editor(Map.put(attrs, :origin, "tei"))
  defp create_source(attrs), do: Catalogue.create_play_source(Map.put(attrs, :origin, "tei"))

  defp create_note(attrs),
    do: Catalogue.create_play_editorial_note(Map.put(attrs, :origin, "tei"))

  defp import_header({_name, _attrs, children}) do
    file_desc = find_child(children, "fileDesc")
    encoding_desc = find_child(children, "encodingDesc")
    profile_desc = find_child(children, "profileDesc")

    play_attrs = extract_play_attrs(file_desc, encoding_desc, profile_desc)

    play =
      case Repo.get_by(Play, code: play_attrs.code) do
        %Play{} = existing_play ->
          reset_tei_content(existing_play)

          case Catalogue.update_play(existing_play, Map.drop(play_attrs, @platform_owned)) do
            {:ok, play} ->
              # An import of an archived play brings it back — the file is the reason it
              # is wanted again.
              play |> Ecto.Changeset.change(deleted_at: nil) |> Repo.update!()

            {:error, changeset} ->
              Repo.rollback(changeset)
          end

        nil ->
          case Catalogue.create_play(play_attrs) do
            {:ok, play} ->
              play

            {:error, changeset} ->
              Repo.rollback(changeset)
          end
      end

    if file_desc do
      import_editors(file_desc, play)
      import_sources(file_desc, play)
    end

    import_places(profile_desc, play)

    play
  end

  defp extract_play_attrs(file_desc, encoding_desc, profile_desc) do
    title_stmt = file_desc && find_child(elem(file_desc, 2), "titleStmt")
    publication_stmt = file_desc && find_child(elem(file_desc, 2), "publicationStmt")
    extent = file_desc && find_child(elem(file_desc, 2), "extent")

    titles = if title_stmt, do: find_children(elem(title_stmt, 2), "title"), else: []
    authors = if title_stmt, do: find_children(elem(title_stmt, 2), "author"), else: []

    # Title selection: prefer <title type="traduccion">, then first <title> without key/type, then fallback
    traduccion_title =
      Enum.find(titles, fn {_, attrs, _} -> attr_value(attrs, "type") == "traduccion" end)

    plain_title =
      Enum.find(titles, fn {_, attrs, _} ->
        !has_attr?(attrs, "key") and !has_attr?(attrs, "type")
      end)

    main_title =
      traduccion_title || plain_title ||
        Enum.find(titles, fn {_, attrs, _} -> !has_attr?(attrs, "key") end)

    sort_title = Enum.find(titles, fn {_, attrs, _} -> attr_value(attrs, "key") == "orden" end)
    code_title = Enum.find(titles, fn {_, attrs, _} -> attr_value(attrs, "key") == "archivo" end)

    original_title_el =
      Enum.find(titles, fn {_, attrs, _} -> attr_value(attrs, "type") == "original" end)

    edition_title_el =
      Enum.find(titles, fn {_, attrs, _} -> attr_value(attrs, "type") == "edicion" end)

    # Determine relationship type from title types
    relationship_type = if traduccion_title, do: "traduccion", else: nil

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

    attribution =
      if main_author do
        attr_value(elem(main_author, 1), "ana")
      end

    %{
      title: safe_text(main_title) |> normalize_imported_title(),
      title_sort: safe_text(sort_title),
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
      language: language || "es",
      composition_date_from: composition_from,
      composition_date_to: composition_to,
      composition_date_note: composition_note
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
  # not roll back the import: `import_tree` rollbacks discard the text, the characters
  # and the acts too. Per the S2c spec, a file that carries no machine dating is the
  # file's problem, not an import failure.
  defp extract_creation(nil), do: {nil, nil, nil}

  defp extract_creation({_name, _attrs, children}) do
    with creation when not is_nil(creation) <- find_child(children, "creation"),
         date when not is_nil(date) <- find_child(elem(creation, 2), "date"),
         {from, to} <- creation_years(elem(date, 1)),
         true <- usable_creation_years?(from, to) do
      {from, to, creation_note(date)}
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

  defp creation_note(date) do
    case date |> text_content() |> String.trim() do
      "" -> nil
      text -> text
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
    availability_text =
      case availability do
        {_, _, avail_children} ->
          avail_children
          |> Enum.filter(fn
            {"p", _, _} -> true
            _ -> false
          end)
          |> Enum.map(&text_content/1)
          |> Enum.join("\n\n")
          |> String.trim()
          |> case do
            "" -> nil
            t -> t
          end

        _ ->
          safe_text(availability)
      end

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

    {
      safe_text(project_desc),
      safe_text(editorial_decl)
    }
  end

  # --- Editors ---

  defp import_editors(file_desc, play) do
    title_stmt = find_child(elem(file_desc, 2), "titleStmt")
    edition_stmt = find_child(elem(file_desc, 2), "editionStmt")

    # Principal investigator and titleStmt editors
    if title_stmt do
      title_stmt_children = elem(title_stmt, 2)

      principal = find_child(title_stmt_children, "principal")

      if principal do
        create_editor(%{
          play_id: play.id,
          person_name: text_content(principal),
          role: "principal",
          position: 0
        })
      end

      # <editor role="…"> in titleStmt: translators, researchers and the editor of the
      # critical edition the text is based on. Any other role (canon60) is skipped.
      title_editors = find_children(title_stmt_children, "editor")

      title_editors
      |> Enum.with_index(1)
      |> Enum.each(fn {{_, attrs, ed_children}, idx} ->
        role = attr_value(attrs, "role")

        normalized_role =
          case role do
            "translator" -> "translator"
            "traductor" -> "translator"
            "researcher" -> "researcher"
            "edicion_critica" -> "critical_editor"
            _ -> nil
          end

        if normalized_role do
          # Name may be in <persName> or direct text
          person_name =
            case find_child(ed_children, "persName") do
              nil -> text_content({"editor", attrs, ed_children})
              el -> text_content(el)
            end

          create_editor(%{
            play_id: play.id,
            person_name: person_name,
            role: normalized_role,
            organization: safe_text(find_child(ed_children, "orgName")),
            position: idx
          })
        end
      end)

      # respStmt elements in titleStmt (common in EMOTHE files)
      resp_stmts_in_title = find_children(title_stmt_children, "respStmt")

      resp_stmts_in_title
      |> Enum.with_index(100)
      |> Enum.each(fn {{_name, _attrs, children}, idx} ->
        person = find_child(children, "persName")
        org = find_child(children, "orgName")
        resp = find_child(children, "resp")

        role =
          case safe_text(resp) do
            text when is_binary(text) ->
              cond do
                String.contains?(text, "Edición") -> "editor"
                String.contains?(text, "Revisión") -> "reviewer"
                true -> "digital_editor"
              end

            _ ->
              "digital_editor"
          end

        if person do
          create_editor(%{
            play_id: play.id,
            person_name: text_content(person),
            role: role,
            organization: safe_text(org),
            position: idx
          })
        end
      end)
    end

    # Edition editors (from editionStmt)
    if edition_stmt do
      resp_stmts = find_children(elem(edition_stmt, 2), "respStmt")

      resp_stmts
      |> Enum.with_index(200)
      |> Enum.each(fn {{_name, _attrs, children}, idx} ->
        person = find_child(children, "persName")
        org = find_child(children, "orgName")
        resp = find_child(children, "resp")

        role =
          case safe_text(resp) do
            text when is_binary(text) ->
              cond do
                String.contains?(text, "Edición") -> "editor"
                String.contains?(text, "Revisión") -> "reviewer"
                true -> "digital_editor"
              end

            _ ->
              "digital_editor"
          end

        if person do
          create_editor(%{
            play_id: play.id,
            person_name: text_content(person),
            role: role,
            organization: safe_text(org),
            position: idx
          })
        end
      end)
    end
  end

  # --- Sources ---

  defp import_sources(file_desc, play) do
    source_desc = find_child(elem(file_desc, 2), "sourceDesc")

    if source_desc do
      # Look for <bibl> directly under <sourceDesc>, or inside <listBibl>
      bibls =
        case find_child(elem(source_desc, 2), "listBibl") do
          nil -> find_children(elem(source_desc, 2), "bibl")
          list_bibl -> find_children(elem(list_bibl, 2), "bibl")
        end

      bibls
      |> Enum.with_index()
      |> Enum.each(fn {{_name, _attrs, children}, idx} ->
        editor_el = find_child(children, "editor")

        editor_role =
          case editor_el do
            {_, attrs, _} -> attr_value(attrs, "role")
            _ -> nil
          end

        create_source(%{
          play_id: play.id,
          title: safe_text(find_child(children, "title")),
          author: safe_text(find_child(children, "author")),
          editor: safe_text(editor_el),
          editor_role: editor_role,
          publisher: safe_text(find_child(children, "publisher")),
          pub_place: safe_text(find_child(children, "pubPlace")),
          pub_date: safe_text(find_child(children, "date")),
          note: safe_text(find_child(children, "note")),
          language: safe_text(find_child(children, "lang")),
          position: idx
        })
      end)
    end
  end

  # --- Places ---

  # `listPlace` supplies the places and their containment; `setting` supplies this
  # play's links. Reading them separately is what keeps a pure container — Italia in
  # `<place xml:id="italia">…<place xml:id="roma">` — from becoming a setting.
  defp import_places(nil, _play), do: :ok

  defp import_places({_name, _attrs, children}, play) do
    case find_child(children, "settingDesc") do
      nil ->
        :ok

      {_n, _a, setting_children} ->
        list_place = find_child(setting_children, "listPlace")
        setting = find_child(setting_children, "setting")

        if list_place, do: import_list_place(list_place, nil)
        if setting, do: import_setting(setting, play)

        :ok
    end
  end

  defp import_list_place({_name, _attrs, children}, parent_id) do
    children
    |> Enum.filter(&match?({"place", _, _}, &1))
    |> Enum.each(&import_place(&1, parent_id))
  end

  defp import_place({_name, attrs, children} = place_el, parent_id) do
    declared_slug = attr_value(attrs, "xml:id")
    slug = declared_slug || Places.slugify(first_place_name(children))
    {latitude, longitude} = place_geo(children)

    place_attrs =
      %{
        "slug" => slug,
        "type" => attr_value(attrs, "type") || "other",
        "parent_place_id" => parent_id,
        "is_fictional" => attr_value(attrs, "subtype") == "fictional",
        "latitude" => latitude,
        "longitude" => longitude,
        "note" => place_note(children),
        "names" => place_names(children)
      }
      |> Map.merge(place_idno(children))

    case Places.find_or_create_by_slug(place_attrs) do
      {:ok, place, outcome} ->
        cond do
          outcome != :existing ->
            :ok

          # No xml:id means the slug was derived from the name, so two distinct
          # referents that happen to share a name silently become one row. Our own
          # exporter always writes xml:id; a hand-authored file may not.
          is_nil(declared_slug) ->
            Logger.warning(
              "TEI import: <place> without xml:id resolved to existing place #{inspect(slug)} " <>
                "by name — if these are different places, give each an xml:id"
            )

          true ->
            Logger.info("TEI import: place #{slug} already exists, left unchanged")
        end

        # Nested <place> elements are this place's children.
        import_list_place(place_el, place.id)

      {:error, changeset} ->
        Logger.warning("TEI import: could not create place #{slug}: #{inspect(changeset.errors)}")
    end
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

  defp import_setting({_name, _attrs, children}, play) do
    children
    |> Enum.filter(&match?({"placeName", _, _}, &1))
    |> Enum.with_index()
    |> Enum.each(fn {{_n, attrs, name_children}, index} ->
      slug = attrs |> attr_value("ref") |> to_string() |> String.trim_leading("#")

      case Repo.get_by(Places.Place, slug: slug) do
        nil ->
          Logger.warning("TEI import: setting references unknown place #{inspect(slug)}")

        place ->
          link_attrs = %{
            "role" => attr_value(attrs, "ana") || "setting",
            "position" => index,
            "note" => setting_note(name_children),
            "origin" => "tei"
          }

          # A hand-linked place (origin "manual") surviving from before this file ever
          # mentioned it collides with the (play_id, place_id) unique index on a blind
          # insert — reset_tei_content only clears this play's own "tei" links, on
          # purpose. Leave the curated row alone: writing "tei" over its origin would
          # hand it to reset_tei_content, and the next re-import would delete it along
          # with its note. Only a link this importer already owns gets refreshed.
          case Repo.get_by(Places.PlayPlace, play_id: play.id, place_id: place.id) do
            nil ->
              Places.link_place(play.id, place.id, link_attrs)

            %{origin: "tei"} = existing ->
              Places.update_play_place(existing, link_attrs)

            existing ->
              Logger.info(
                "TEI import: <setting> names #{inspect(slug)}, already linked with " <>
                  "origin #{inspect(existing.origin)} — left untouched"
              )
          end
      end
    end)
  end

  # A link's note is a bare `<note>` inside `<setting>/<placeName>` — no `type`
  # attribute, and one tree level deeper than a place's own `<note type="place">`.
  defp setting_note(children) do
    case find_child(children, "note") do
      nil -> nil
      el -> text_content(el)
    end
  end

  # --- Text content (front, body, back) ---

  defp import_text({_name, _attrs, children}, play) do
    front = find_child(children, "front")
    body = find_child(children, "body")

    position = 0

    position =
      if front do
        import_front(front, play, position)
      else
        position
      end

    if body do
      import_body(body, play, position)
    end
  end

  # --- Front matter ---

  defp import_front({_name, _attrs, children}, play, start_pos) do
    # Import cast list and front matter divs
    pos = start_pos

    Enum.reduce(children, pos, fn
      {"titlePage", _attrs, _children}, acc ->
        # Skip title page, it's metadata we already have
        acc

      {"div", attrs, div_children} = _div, acc ->
        type = attr_value(attrs, "type") || "front"
        import_front_div(type, div_children, play, acc)

      _, acc ->
        acc
    end)
  end

  defp import_front_div("elenco", children, play, pos) do
    # Cast list
    cast_list = find_child(children, "castList")

    if cast_list do
      import_cast_list(cast_list, play)
    end

    # Create a division for the elenco
    case PlayContent.create_division(%{
           play_id: play.id,
           type: "elenco",
           title: safe_text(find_child(children, "head")),
           position: pos
         }) do
      {:ok, _div} -> :ok
      {:error, cs} -> Repo.rollback({:division_create_failed, cs})
    end

    pos + 1
  end

  defp import_front_div(type, children, play, pos) do
    # Generic front matter div (dedication, editorial note, etc.)
    heading = safe_text(find_child(children, "head"))

    # Store as editorial note
    paragraphs =
      children
      |> find_children("p")
      |> Enum.map(&text_content/1)
      |> Enum.join("\n\n")

    if paragraphs != "" do
      section_type =
        case type do
          "introduccion_editor" -> "introduccion_editor"
          "dedicatoria" -> "dedicatoria"
          "argumento" -> "argumento"
          "prologo" -> "prologo"
          _ -> "nota"
        end

      create_note(%{
        play_id: play.id,
        section_type: section_type,
        heading: heading,
        content: paragraphs,
        position: pos
      })
    end

    pos + 1
  end

  # --- Cast list ---

  defp import_cast_list({_name, _attrs, children}, play) do
    cast_items = find_children(children, "castItem")

    cast_items
    |> Enum.with_index()
    |> Enum.each(fn {{_name, attrs, item_children}, idx} ->
      role = find_child(item_children, "role")
      role_desc = find_child(item_children, "roleDesc")
      is_hidden = attr_value(attrs, "ana") == "oculto"

      if role do
        {_role_name, role_attrs, _role_children} = role
        xml_id = attr_value(role_attrs, "xml:id") || attr_value(role_attrs, "id")
        name = text_content(role) |> String.trim()

        # Clean xml_id (some have newlines)
        xml_id = if xml_id, do: String.trim(xml_id), else: name

        PlayContent.create_character_unless_exists(%{
          play_id: play.id,
          xml_id: xml_id,
          name: name,
          description: safe_text(role_desc),
          is_hidden: is_hidden,
          position: idx
        })
      end
    end)
  end

  # --- Body (acts, scenes, speeches, etc.) ---

  defp import_body({_name, _attrs, children}, play, start_pos) do
    children
    |> Enum.filter(fn
      {name, _, _} -> name in ["div1", "div"]
      _ -> false
    end)
    |> Enum.with_index(start_pos)
    |> Enum.each(fn {{_name, attrs, act_children}, pos} ->
      type = (attr_value(attrs, "type") || "acto") |> String.downcase()
      number = parse_int(attr_value(attrs, "n"))
      {heading, head_notes} = text_and_notes(find_child(act_children, "head"))

      act_div =
        case PlayContent.create_division(%{
               play_id: play.id,
               type: type,
               number: number,
               title: heading,
               position: pos
             }) do
          {:ok, div} -> div
          {:error, cs} -> Repo.rollback({:division_create_failed, cs})
        end

      create_text_notes(%{division_id: act_div.id}, head_notes, play)

      import_act_content(act_children, play, act_div)
    end)
  end

  defp import_act_content(children, play, act_div) do
    # Process children sequentially, tracking element position
    {_pos, _scene_pos} =
      Enum.reduce(children, {0, 0}, fn
        {"head", _, _}, acc ->
          # Already handled as division title
          acc

        {"div2", attrs, scene_children}, {el_pos, scene_pos} ->
          # Scene subdivision
          scene_type = (attr_value(attrs, "type") || "escena") |> String.downcase()
          number = parse_int(attr_value(attrs, "n"))
          {heading, head_notes} = text_and_notes(find_child(scene_children, "head"))

          scene_div =
            case PlayContent.create_division(%{
                   play_id: play.id,
                   parent_id: act_div.id,
                   type: scene_type,
                   number: number,
                   title: heading,
                   position: scene_pos
                 }) do
              {:ok, div} -> div
              {:error, cs} -> Repo.rollback({:division_create_failed, cs})
            end

          create_text_notes(%{division_id: scene_div.id}, head_notes, play)

          new_el_pos = import_scene_content(scene_children, play, scene_div, el_pos)
          {new_el_pos, scene_pos + 1}

        {"sp", attrs, sp_children}, {el_pos, scene_pos} ->
          new_pos = import_speech(attrs, sp_children, play, act_div, el_pos)
          {new_pos, scene_pos}

        {"stage", _attrs, _} = stage, {el_pos, scene_pos} ->
          import_stage_direction(stage, play, act_div, nil, el_pos)
          {el_pos + 1, scene_pos}

        {"p", _, _} = para, {el_pos, scene_pos} ->
          import_prose(para, play, act_div, nil, el_pos)
          {el_pos + 1, scene_pos}

        {"lg", attrs, lg_children}, {el_pos, scene_pos} ->
          {import_line_group(attrs, lg_children, play, act_div, nil, el_pos), scene_pos}

        {"trailer", _, _} = trailer, {el_pos, scene_pos} ->
          import_trailer(trailer, play, act_div, el_pos)
          {el_pos + 1, scene_pos}

        _, acc ->
          acc
      end)
  end

  defp import_scene_content(children, play, scene_div, start_pos) do
    Enum.reduce(children, start_pos, fn
      {"head", _, _}, pos ->
        pos

      {"sp", attrs, sp_children}, pos ->
        import_speech(attrs, sp_children, play, scene_div, pos)

      {"stage", _, _} = stage, pos ->
        import_stage_direction(stage, play, scene_div, nil, pos)
        pos + 1

      {"trailer", _, _} = trailer, pos ->
        import_trailer(trailer, play, scene_div, pos)
        pos + 1

      _, pos ->
        pos
    end)
  end

  # --- Speech ---

  defp import_speech(attrs, children, play, division, start_pos) do
    who = attr_value(attrs, "who")
    speaker_elem = find_child(children, "speaker")
    {speaker_label, speaker_notes} = text_and_notes(speaker_elem)

    # Resolve characters from who attribute (supports multi-character who="#ALB #COR")
    character_ids = resolve_characters(play.id, who)

    speech =
      case PlayContent.create_element(%{
             play_id: play.id,
             division_id: division.id,
             type: "speech",
             speaker_label: speaker_label,
             position: start_pos
           }) do
        {:ok, el} -> el
        {:error, cs} -> Repo.rollback({:element_create_failed, :speech, cs})
      end

    create_text_notes(%{element_id: speech.id}, speaker_notes, play)

    # Associate characters with the speech
    if character_ids != [] do
      PlayContent.set_element_characters(speech.id, character_ids)
    end

    # Import child elements (lg groups, individual l elements, stage directions, p elements)
    _child_pos =
      Enum.reduce(children, 0, fn
        {"speaker", _, _}, pos ->
          pos

        {"lg", attrs, lg_children}, pos ->
          import_line_group(attrs, lg_children, play, division, speech.id, pos)

        {"l", _, _} = line, pos ->
          import_verse_line(line, play, division, speech, pos)
          pos + 1

        {"stage", _, _} = stage, pos ->
          import_stage_direction(stage, play, division, speech.id, pos)
          pos + 1

        {"p", _, _} = para, pos ->
          import_prose(para, play, division, speech.id, pos)
          pos + 1

        _, pos ->
          pos
      end)

    start_pos + 1
  end

  # --- Line group ---

  defp import_line_group(attrs, children, play, division, parent_id, start_pos) do
    verse_type = attr_value(attrs, "type")
    part = attr_value(attrs, "part")

    lg =
      case PlayContent.create_element(%{
             play_id: play.id,
             division_id: division.id,
             parent_id: parent_id,
             type: "line_group",
             verse_type: verse_type,
             part: part,
             position: start_pos
           }) do
        {:ok, el} -> el
        {:error, cs} -> Repo.rollback({:element_create_failed, :line_group, cs})
      end

    Enum.reduce(children, 0, fn
      {"l", _, _} = line, pos ->
        import_verse_line(line, play, division, lg, pos)
        pos + 1

      {"stage", _, _} = stage, pos ->
        import_stage_direction(stage, play, division, lg.id, pos)
        pos + 1

      _, pos ->
        pos
    end)

    start_pos + 1
  end

  # --- Verse line ---

  defp import_verse_line(
         {name, attrs, children},
         play,
         division,
         parent,
         pos
       ) do
    line_id = attr_value(attrs, "xml:id") || attr_value(attrs, "id")
    line_number = parse_int(attr_value(attrs, "n"))
    part = attr_value(attrs, "part")
    rend = attr_value(attrs, "rend")
    is_aside = aside_delivery?(children)
    line = {name, attrs, children}
    {content, notes} = line |> verse_line_content(is_aside) |> take_notes(line)

    case PlayContent.create_element(%{
           play_id: play.id,
           division_id: division.id,
           parent_id: parent.id,
           type: "verse_line",
           content: content,
           line_number: line_number,
           line_id: line_id,
           part: part,
           rend: rend,
           is_aside: is_aside,
           position: pos
         }) do
      {:ok, el} -> create_text_notes(%{element_id: el.id}, notes, play)
      {:error, cs} -> Repo.rollback({:element_create_failed, :verse_line, cs})
    end
  end

  # Returns true if the children of an <l> element indicate an aside, either via:
  # - <stage type="delivery">[Aparte.]</stage>
  # - <seg type="aside">...</seg>
  defp aside_delivery?(children) when is_list(children) do
    Enum.any?(children, fn
      {"stage", attrs, stage_children} ->
        attr_value(attrs, "type") == "delivery" and
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
  # is its <seg type="aside"> text, with the line's own notes kept beside it; with no
  # <seg>, the line without its delivery <stage>.
  defp verse_line_content({_name, _attrs, children}, true) do
    if aside_in_children?(children) do
      aside_content(children)
    else
      children
      |> Enum.reject(&match?({"stage", _, _}, &1))
      |> pieces(:mark, &text_content(&1, :mark))
      |> squeeze()
    end
  end

  defp verse_line_content(line, false), do: text_content(line, :mark)

  defp aside_seg?({"seg", attrs, _}), do: attr_value(attrs, "type") == "aside"
  defp aside_seg?(_), do: false

  # --- Stage direction ---

  defp import_stage_direction({_name, attrs, _children} = stage, play, division, parent_id, pos) do
    {content, notes} = text_and_notes(stage)

    case PlayContent.create_element(%{
           play_id: play.id,
           division_id: division.id,
           parent_id: parent_id,
           type: "stage_direction",
           content: content,
           stage_type: attr_value(attrs, "type"),
           position: pos
         }) do
      {:ok, el} -> create_text_notes(%{element_id: el.id}, notes, play)
      {:error, cs} -> Repo.rollback({:element_create_failed, :stage_direction, cs})
    end
  end

  # --- Trailer ---

  defp import_trailer(trailer, play, division, pos) do
    {content, notes} = text_and_notes(trailer)

    case PlayContent.create_element(%{
           play_id: play.id,
           division_id: division.id,
           type: "trailer",
           content: content,
           position: pos
         }) do
      {:ok, el} -> create_text_notes(%{element_id: el.id}, notes, play)
      {:error, cs} -> Repo.rollback({:element_create_failed, :trailer, cs})
    end
  end

  # --- Prose ---

  defp import_prose({_name, _attrs, children} = para, play, division, parent_id, pos) do
    is_aside = aside_in_children?(children)
    marked = if is_aside, do: aside_content(children), else: text_content(para, :mark)
    {content, notes} = take_notes(marked, para)

    case PlayContent.create_element(%{
           play_id: play.id,
           division_id: division.id,
           parent_id: parent_id,
           type: "prose",
           content: content,
           is_aside: is_aside,
           position: pos
         }) do
      {:ok, el} -> create_text_notes(%{element_id: el.id}, notes, play)
      {:error, cs} -> Repo.rollback({:element_create_failed, :prose, cs})
    end
  end

  # Check if children contain a <seg type="aside"> element
  defp aside_in_children?(children) when is_list(children), do: Enum.any?(children, &aside_seg?/1)

  defp aside_in_children?(_), do: false

  # An aside line's or paragraph's <seg type="aside"> text, with its own notes beside it.
  defp aside_content(children) do
    children
    |> Enum.filter(&(aside_seg?(&1) or match?({"note", _, _}, &1)))
    |> pieces(:mark, &text_content(&1, :mark))
    |> squeeze()
  end

  # --- Character resolution ---

  defp resolve_characters(_play_id, nil), do: []

  defp resolve_characters(play_id, who) do
    # who can be "#ALFONSO" (single) or "#ALB #COR" (multi-character, space-separated)
    who
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map(fn ref ->
      xml_id = ref |> String.replace("#", "") |> String.trim()
      PlayContent.find_character_by_xml_id(play_id, xml_id)
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(& &1.id)
    # A who attribute may repeat the same ref (e.g. "#horatio #barnardo #marcellus #barnardo")
    # which would otherwise violate the element_characters unique index.
    |> Enum.uniq()
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
  # (:mark, the play text), which take_notes/2 turns into the note's offset.
  defp text_content(element, notes \\ :paste)

  defp text_content({name, attrs, children}, notes) do
    if emph_element?(name, attrs) do
      "<<" <> extract_plain_text(children, notes) <> ">>"
    else
      children |> pieces(notes, &text_content(&1, notes)) |> squeeze()
    end
  end

  defp text_content(text, _notes) when is_binary(text), do: String.trim(text)
  defp text_content(_, _notes), do: ""

  defp emph_element?("emph", _attrs), do: true

  defp emph_element?("hi", attrs),
    do: attr_value(attrs, "rend") in ["italic", "italics"]

  defp emph_element?(_, _), do: false

  defp extract_plain_text(children, notes) when is_list(children),
    do: children |> pieces(notes, &extract_plain_text(elem(&1, 2), notes)) |> squeeze()

  # Pieces of text as one string, a space between them, whitespace collapsed.
  defp squeeze(pieces),
    do: pieces |> Enum.join(" ") |> String.replace(~r/\s+/, " ") |> String.trim()

  # Each child's text, read by `fun`; under :mark a <note> child is its mark instead.
  defp pieces(children, notes, fun) do
    children
    |> Enum.with_index()
    |> Enum.map(fn
      {{"note", _, _} = note, i} when notes == :mark -> note_mark(note, children, i)
      {text, _} when is_binary(text) -> String.trim(text)
      {child, _} when is_tuple(child) -> fun.(child)
      _ -> ""
    end)
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
  # Returns the text and `[{offset, note}]`, the offset counting graphemes of the text
  # without its << and >> markers, as InlineMarkup.plain/1 does. A note whose mark the
  # reading dropped (inside a stripped aside <stage>) is dropped with it.
  # ponytail: two adjacent notes each with whitespace beside them ("a <note/><note/> b")
  # store "a  b" and the second note one grapheme later; the corpus has no note after a
  # space. Carry a pending space to the next text if one turns up.
  defp take_notes(marked, element) do
    by_key = Map.new(nested_notes(element), &{Integer.to_string(:erlang.phash2(&1)), &1})

    {text, found} =
      @note_mark
      |> Regex.split(marked, include_captures: true)
      |> Enum.reduce({"", []}, fn piece, {text, found} ->
        case Regex.run(@note_mark, piece) do
          [_, key, spaced] ->
            space = if spaced == "s" and text != "", do: " ", else: ""
            {text <> space, [{plain_length(text), Map.fetch!(by_key, key)} | found]}

          nil ->
            {text <> piece, found}
        end
      end)

    text = String.trim_trailing(text)
    last = plain_length(text)

    {text,
     found |> Enum.reverse() |> Enum.map(fn {offset, note} -> {min(offset, last), note} end)}
  end

  defp plain_length(text), do: String.length(text) - 2 * length(Regex.scan(~r/<<|>>/, text))

  # The <note>s inside an element, not counting notes inside notes.
  defp nested_notes({_name, _attrs, children}) do
    Enum.flat_map(children, fn
      {"note", _, _} = note -> [note]
      {_, _, _} = child -> nested_notes(child)
      _text -> []
    end)
  end

  # An element of the play text read with its notes taken out: `{text, [{offset, note}]}`,
  # or `{nil, []}` for no element.
  defp text_and_notes(nil), do: {nil, []}
  defp text_and_notes(element), do: element |> text_content(:mark) |> take_notes(element)

  # A note's own fields, or nil when it has no text: there is nothing to show (the
  # empty notes of the EMOTHE0010 test file).
  defp parse_note({"note", attrs, children}) do
    body =
      case find_children(children, "p") do
        [] ->
          text_content({"note", attrs, Enum.reject(children, &match?({"term", _, _}, &1))})

        paragraphs ->
          paragraphs
          |> Enum.map(&text_content/1)
          |> Enum.reject(&(&1 == ""))
          |> Enum.join("\n\n")
      end

    term = safe_text(find_child(children, "term"))

    if body != "" do
      %{
        n: attr_value(attrs, "n"),
        type: attr_value(attrs, "type"),
        term: if(term in [nil, ""], do: nil, else: term),
        body: body
      }
    end
  end

  # Stores the notes take_notes/2 found on `anchor`, %{element_id: id} or
  # %{division_id: id}, in document order: `create_note/1` puts each after the notes
  # already at its offset.
  defp create_text_notes(anchor, notes, play) do
    Enum.each(notes, fn {offset, note} ->
      with %{} = fields <- parse_note(note) do
        attrs =
          fields
          |> Map.merge(anchor)
          |> Map.merge(%{play_id: play.id, offset: offset})

        case PlayContent.create_note(attrs) do
          {:ok, _note} -> :ok
          {:error, cs} -> Repo.rollback({:note_create_failed, cs})
        end
      end
    end)
  end

  defp safe_text(nil), do: nil
  defp safe_text(element) when is_tuple(element), do: text_content(element)
  defp safe_text(text) when is_binary(text), do: String.trim(text)

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
