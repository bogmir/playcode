defmodule Playcode.Export.StaticSite.Renderer do
  @moduledoc """
  Pure-function HTML renderer for the static site.
  No Phoenix/LiveView dependencies. Uses string interpolation only.
  """

  @act_types ~w(acto act acte jornada)

  # --- Public API ---

  def catalogue_page(plays, opts) do
    version = opts[:version] || "1.0"
    build_date = opts[:build_date] || Date.utc_today() |> Date.to_iso8601()

    play_entries =
      plays
      |> Enum.map(&render_catalogue_entry/1)
      |> Enum.join("\n")

    """
    <!DOCTYPE html>
    <html lang="es">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>EMOTHE — Digital Library of European Early Modern Theatre</title>
      <link rel="stylesheet" href="style.css">
    </head>
    <body>
      <nav class="site-nav">
        <a href="index.html" class="nav-brand">EMOTHE</a>
        <span class="nav-subtitle">Digital Library of European Early Modern Theatre</span>
      </nav>

      <main class="page catalogue-page">
        <h1>Play Catalogue</h1>

        <div class="search-box">
          <input type="text" id="catalogue-search" placeholder="Search by title, author, or code..." autocomplete="off">
          <noscript><p class="noscript-note">Enable JavaScript for interactive search. All plays are listed below.</p></noscript>
        </div>

        <p class="catalogue-count" id="catalogue-count">#{length(plays)} plays</p>
        <p class="no-results" id="no-results" style="display:none;">No plays match your search.</p>

        <div class="catalogue-list" id="catalogue-list">
    #{play_entries}
        </div>
      </main>

      #{footer(version, build_date)}
      <script src="search.js"></script>
    </body>
    </html>
    """
  end

  def play_page(play, characters, divisions, statistic, opts) do
    version = opts[:version] || "1.0"
    build_date = opts[:build_date] || Date.utc_today() |> Date.to_iso8601()

    """
    <!DOCTYPE html>
    <html lang="#{play.language || "es"}">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>#{escape(play.title)} — #{escape(play.author_name || "")} — EMOTHE</title>
      <link rel="stylesheet" href="../style.css">
    </head>
    <body>
      <nav class="site-nav">
        <a href="../index.html" class="nav-brand">EMOTHE</a>
        <span class="nav-sep">›</span>
        <a href="../index.html" class="nav-link">Catalogue</a>
        <span class="nav-sep">›</span>
        <span class="nav-current">#{escape(play.code)}</span>
      </nav>

      <main class="page play-page">
        <header class="header">
          <p class="author">#{escape(play.author_name || "")}</p>
          <h1 class="title">#{escape(play.title)}</h1>
    #{render_sources(play.sources)}
    #{render_editors(play.editors)}
    #{render_verse_info(play)}
    #{render_places(play)}
    #{render_study(play)}
          <p class="tei-link"><a href="#{escape_attr(play.code)}.xml">Download TEI-XML source</a></p>
        </header>

        <nav class="section-nav">
          <a href="#text">Text</a>
          <a href="#characters">Characters</a>
          <a href="#statistics">Statistics</a>
        </nav>

    #{render_division_nav(divisions)}

        <section id="text">
          <h2 class="section-heading">Text</h2>
    #{render_editorial_notes(play.editorial_notes)}
          <div class="play-text">
    #{render_divisions(divisions, characters)}
          </div>
        </section>

        <section id="characters">
          <h2 class="section-heading">Characters</h2>
    #{render_characters_table(characters)}
        </section>

        <section id="statistics">
          <h2 class="section-heading">Statistics</h2>
    #{render_statistics(statistic)}
        </section>
      </main>

      #{footer(version, build_date)}
    </body>
    </html>
    """
  end

  def site_css do
    """
    /* EMOTHE Static Site — Endings-compliant, no external dependencies */
    *, *::before, *::after { margin: 0; padding: 0; box-sizing: border-box; }

    body {
      background-color: #faf5ee;
      font-family: Verdana, Geneva, sans-serif;
      line-height: 160%;
      color: #333;
    }

    /* Navigation */
    .site-nav {
      background: #2c2416;
      color: #d4c9a8;
      padding: 0.75rem 1.5rem;
      display: flex;
      align-items: center;
      gap: 0.5rem;
      font-size: 0.875rem;
    }
    .nav-brand {
      font-weight: bold;
      font-size: 1.1rem;
      color: #f5e6c8;
      text-decoration: none;
    }
    .nav-brand:hover { color: #fff; }
    .nav-subtitle { color: #a89878; font-size: 0.8rem; margin-left: 0.5rem; }
    .nav-sep { color: #6b5e4a; }
    .nav-link { color: #d4c9a8; text-decoration: none; }
    .nav-link:hover { color: #fff; text-decoration: underline; }
    .nav-current { color: #f5e6c8; }

    /* Page container */
    .page {
      max-width: 800px;
      margin: 0 auto;
      padding: 2rem 1.5rem;
    }

    /* Catalogue page */
    .catalogue-page h1 {
      font-family: Georgia, "Times New Roman", Times, serif;
      font-size: 1.5rem;
      margin-bottom: 1.5rem;
      text-align: center;
    }
    .search-box {
      max-width: 500px;
      margin: 0 auto 1rem;
    }
    .search-box input {
      width: 100%;
      padding: 0.6rem 1rem;
      border: 1px solid #ccc;
      border-radius: 6px;
      font-size: 0.95rem;
      background: #fff;
      color: #333;
    }
    .search-box input:focus { outline: 2px solid #8b7355; border-color: #8b7355; }
    .noscript-note { font-size: 0.8rem; color: #888; margin-top: 0.25rem; }
    .catalogue-count {
      text-align: center;
      font-size: 0.85rem;
      color: #888;
      margin-bottom: 1rem;
    }
    .no-results {
      text-align: center;
      font-size: 0.95rem;
      color: #888;
      padding: 2rem 0;
    }
    .catalogue-list { display: flex; flex-direction: column; gap: 0.5rem; }
    .play-entry {
      padding: 0.75rem 1rem;
      border: 1px solid #e5e0d5;
      border-radius: 6px;
      background: #fff;
    }
    .play-entry:hover { border-color: #c5b99a; }
    .play-entry-row1 {
      display: flex;
      align-items: center;
      justify-content: space-between;
    }
    .play-entry-row2 {
      display: flex;
      align-items: center;
      gap: 0.5rem;
      margin-top: 0.15rem;
    }
    .play-code {
      font-size: 0.7rem;
      font-family: monospace;
      color: #8b7355;
      white-space: nowrap;
    }
    .play-title-link {
      color: #333;
      text-decoration: none;
      font-weight: 600;
    }
    .play-title-link:hover { color: #8b7355; text-decoration: underline; }
    .play-tei-link {
      font-size: 0.7rem;
      color: #8b7355;
      text-decoration: none;
      margin-left: auto;
      flex-shrink: 0;
    }
    .play-tei-link:hover { text-decoration: underline; }
    .play-author { font-size: 0.85rem; color: #7E7B6A; margin-top: 0.15rem; }
    .play-meta {
      font-size: 0.75rem;
      color: #aaa;
      display: flex;
      gap: 0.5rem;
      margin-top: 0.15rem;
    }
    .play-badge {
      font-size: 0.65rem;
      padding: 0.1rem 0.4rem;
      border-radius: 3px;
      background: #eee;
      color: #666;
      text-transform: uppercase;
      min-width: 1.75rem;
      text-align: center;
    }

    /* Play page header */
    .header {
      text-align: center;
      font-family: Georgia, "Times New Roman", Times, serif;
      border-bottom: 1px solid #ddd;
      padding-bottom: 1.5rem;
      margin-bottom: 2rem;
    }
    .header .author { font-size: 17px; color: #7E7B6A; }
    .header .title { font-size: 20px; font-weight: bold; text-transform: uppercase; }
    .header .source-note {
      margin-top: 1rem; font-size: 0.75rem;
      color: rgba(51,51,51,0.5); font-style: italic;
    }
    .header .editors {
      margin-top: 0.75rem; font-size: 0.75rem; color: rgba(51,51,51,0.5);
    }
    .header .editors .role { color: rgba(51,51,51,0.35); }
    .header .verse-info {
      margin-top: 0.5rem; font-size: 0.75rem; color: rgba(51,51,51,0.5);
    }
    .tei-link { margin-top: 0.75rem; font-size: 0.8rem; }
    .tei-link a { color: #8b7355; text-decoration: none; }
    .tei-link a:hover { text-decoration: underline; }

    /* Section navigation */
    .section-nav {
      display: flex;
      justify-content: center;
      gap: 2rem;
      padding: 0.75rem 0;
      border-bottom: 1px solid #e5e0d5;
      margin-bottom: 2rem;
    }
    .section-nav a {
      color: #8b7355;
      text-decoration: none;
      font-weight: 600;
      font-size: 0.95rem;
    }
    .section-nav a:hover { text-decoration: underline; }

    .division-nav {
      display: flex;
      flex-wrap: wrap;
      justify-content: center;
      gap: 0.25rem 1.5rem;
      padding: 0.5rem 0;
      border-bottom: 1px solid #e5e0d5;
      margin-bottom: 2rem;
      font-size: 0.8rem;
    }
    .division-nav-group { display: flex; align-items: baseline; gap: 0.25rem; }
    .division-nav a { color: #8b7355; text-decoration: none; }
    .division-nav a:hover { text-decoration: underline; }
    .division-nav .scene-links { font-size: 0.7rem; color: #aaa; }
    .division-nav .scene-links a { color: #b0a080; }

    .section-heading {
      font-family: Georgia, "Times New Roman", Times, serif;
      font-size: 1.25rem;
      margin: 2rem 0 1rem;
      padding-top: 1rem;
      border-top: 1px solid #e5e0d5;
      text-align: center;
    }

    /* Editorial notes */
    .editorial-note {
      max-width: 640px; margin: 0 auto 1.5rem;
      text-align: justify; font-size: 0.875rem; white-space: pre-line;
    }
    .editorial-note h3 { font-weight: bold; text-align: center; margin-bottom: 0.5rem; }
    .editorial-note-sep {
      max-width: 640px; margin: 0 auto 1.5rem;
      border: none; border-top: 1px solid #e5e7eb;
    }

    /* Cast list */
    .cast-list { max-width: 560px; margin: 0 auto 1.5rem; }
    .cast-item {
      display: flex; align-items: baseline; gap: 0.75rem;
      padding: 0.25rem 0; margin-left: 1rem;
    }
    .cast-name { font-weight: bold; font-size: x-small; text-transform: uppercase; flex-shrink: 0; }
    .cast-desc { font-size: 0.875rem; color: rgba(51,51,51,0.55); }

    /* Division headings */
    .act-heading { font-weight: bold; text-align: center; font-size: 1.125rem; margin: 1.5rem 0; }
    .scene-heading { font-weight: bold; text-align: center; font-size: 0.875rem; margin: 1rem 0; }

    /* Speech blocks */
    .speech { margin-top: 0.5rem; margin-bottom: 1.25rem; }
    .speech.aside { padding-left: 2rem; border-left: 2px solid #ccc; }
    .speaker {
      font-weight: bold; font-size: x-small;
      text-transform: uppercase; color: #333; margin-bottom: 0.125rem;
    }

    /* Verse lines */
    .verse-line { display: flex; align-items: baseline; gap: 0.5rem; margin-left: 1rem; }
    .verse-line .content { flex: 1; }
    .verse-line .content.indent { padding-left: 2rem; }
    .verse-line .content.part-m { padding-left: 50px; }
    .verse-line .content.part-f { padding-left: 100px; }
    .line-number {
      width: 2rem; text-align: left; flex-shrink: 0;
      font-size: x-small; color: #999;
      font-variant-numeric: tabular-nums; user-select: none;
    }

    /* Stage directions */
    .stage-direction {
      text-align: center; font-style: italic;
      color: #555; margin: 0.75rem 2rem;
    }

    /* Prose */
    .prose-block { margin-left: 1rem; margin-bottom: 0.5rem; text-align: justify; }

    .division { margin-bottom: 2rem; }
    .child-division { margin-bottom: 1.5rem; }

    /* Characters table */
    .characters-table {
      width: 100%; border-collapse: collapse; margin: 1rem 0;
    }
    .characters-table th {
      text-align: left; border-bottom: 2px solid #ddd;
      padding: 0.5rem 0.75rem; font-size: 0.85rem; color: #666;
    }
    .characters-table td {
      border-bottom: 1px solid #eee;
      padding: 0.4rem 0.75rem; font-size: 0.9rem;
    }
    .characters-table .char-id { font-family: monospace; font-size: 0.8rem; color: #8b7355; }

    /* Statistics */
    .stats-cards {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(140px, 1fr));
      gap: 1rem;
      margin-bottom: 1.5rem;
    }
    .stat-card {
      border: 1px solid #e5e0d5;
      border-radius: 8px;
      padding: 1rem;
      text-align: center;
      background: #fff;
    }
    .stat-card .value { font-size: 1.5rem; font-weight: bold; color: #333; }
    .stat-card .label { font-size: 0.8rem; color: #888; }

    .chart-section {
      border: 1px solid #e5e0d5;
      border-radius: 8px;
      padding: 1.25rem;
      margin-bottom: 1.25rem;
      background: #fff;
    }
    .chart-section h3 { font-size: 1rem; font-weight: 600; margin-bottom: 1rem; }
    .bar-row { display: flex; align-items: center; gap: 0.75rem; margin-bottom: 0.5rem; }
    .bar-label {
      width: 9rem; text-align: right; flex-shrink: 0;
      font-size: 0.85rem; color: #666; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
    }
    .bar-track {
      flex: 1; background: #eee; border-radius: 9999px;
      height: 1.5rem; overflow: hidden;
    }
    .bar-fill {
      height: 100%; border-radius: 9999px;
      display: flex; align-items: center; justify-content: flex-end;
      padding-right: 0.5rem; min-width: 2rem;
    }
    .bar-fill span { font-size: 0.7rem; color: #fff; font-weight: 600; }
    .bar-amber { background-color: #f59e0b; }
    .bar-indigo { background-color: #6366f1; }
    .bar-emerald { background-color: #10b981; }
    .bar-violet { background-color: #8b5cf6; }

    /* Footer */
    .site-footer {
      max-width: 800px; margin: 3rem auto 1rem; padding: 1rem 1.5rem;
      border-top: 1px solid #ddd; text-align: center;
      font-size: 0.75rem; color: #999;
    }

    /* Print */
    @media print {
      body { background: white; }
      .site-nav, .search-box, .section-nav, .site-footer { display: none; }
      .page { max-width: 100%; padding: 0.5rem 0; }
      .header { border-bottom-color: #ccc; }
      .act-heading { page-break-before: always; }
      .speech, .verse-line, .cast-item { break-inside: avoid; }
    }

    /* Responsive */
    @media (max-width: 600px) {
      .page { padding: 1rem 0.75rem; }
      .stats-cards { grid-template-columns: repeat(2, 1fr); }
      .bar-label { width: 5rem; font-size: 0.75rem; }
      .play-entry { flex-direction: column; gap: 0.25rem; }
    }
    """
  end

  # --- Catalogue rendering ---

  defp render_catalogue_entry(play) do
    lang = play.language || ""
    author = play.author_name || ""

    badge =
      if lang != "",
        do: "<span class=\"play-badge\">#{escape(lang)}</span>",
        else: ""

    """
          <div class="play-entry" data-title="#{escape_attr(String.downcase(play.title || ""))}" data-author="#{escape_attr(String.downcase(author))}" data-code="#{escape_attr(String.downcase(play.code || ""))}">
            <div class="play-entry-row1">
              <span class="play-code">#{escape(play.code)}</span>
              <a class="play-tei-link" href="plays/#{escape_attr(play.code)}/#{escape_attr(play.code)}.xml" title="TEI-XML">XML</a>
            </div>
            <div class="play-entry-row2">
              #{badge}<a class="play-title-link" href="plays/#{escape_attr(play.code)}/index.html">#{escape(play.title)}</a>
            </div>
            <div class="play-author">#{escape(author)}</div>
          </div>
    """
  end

  # --- Play text rendering (ported from Export.Html) ---

  defp render_sources(sources) do
    sources
    |> Enum.map(fn s ->
      if s.note,
        do: "      <p class=\"source-note\">#{escape(s.note)}</p>",
        else: ""
    end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp render_editors([]), do: ""

  defp render_editors(editors) do
    items =
      Enum.map(editors, fn ed ->
        "        <span>#{escape(ed.person_name)} <span class=\"role\">(#{escape(ed.role)})</span></span>"
      end)
      |> Enum.join("\n")

    "      <div class=\"editors\">\n#{items}\n      </div>"
  end

  # The archival artifact must not change language with whichever locale the admin
  # running the export happened to have (Ruling 3) — historical_time_label/1 and
  # place_type_label/1 go through gettext, so this is pinned to English explicitly.
  defp render_study(%{
         historical_time: nil,
         composition_date_from: nil,
         composition_date_note: nil
       }),
       do: ""

  defp render_study(play) do
    Gettext.with_locale(PlaycodeWeb.Gettext, "en", fn ->
      [render_historical_time(play), render_composition_date(play)]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join()
    end)
  end

  defp render_historical_time(%{historical_time: nil}), do: ""

  defp render_historical_time(play) do
    """
          <p class="historical-time">Historical time: #{escape(PlaycodeWeb.PlayLabels.historical_time_label(play.historical_time))}</p>
    #{meta_note(play.historical_time_note)}
    """
  end

  # A note with no years is a real state: the changeset permits it and the FileMaker
  # sync writes it, so the note alone must still reach the archive.
  defp render_composition_date(%{composition_date_from: nil, composition_date_note: nil}), do: ""

  defp render_composition_date(play) do
    """
          <p class="composition-date">Composition#{composition_years(play)}</p>
    #{meta_note(play.composition_date_note)}
    """
  end

  # An en dash, collapsing when the dating is a single year, as on the public page.
  # With no years the label stands alone rather than trailing an empty ": ".
  defp composition_years(%{composition_date_from: nil}), do: ""

  defp composition_years(%{composition_date_from: from, composition_date_to: to}) when from == to,
    do: ": #{from}"

  defp composition_years(%{composition_date_from: from, composition_date_to: to}),
    do: ": #{from}–#{to}"

  defp meta_note(nil), do: ""
  defp meta_note(text), do: "<p class=\"meta-note\">#{escape(text)}</p>"

  defp render_places(%{play_places: []}), do: ""

  defp render_places(%{play_places: links}) when is_list(links) do
    Gettext.with_locale(PlaycodeWeb.Gettext, "en", fn ->
      gazetteer = Playcode.Places.gazetteer()

      items =
        links
        |> Enum.sort_by(fn link -> {link.role != "setting", link.position} end)
        |> Enum.map_join("\n", fn link ->
          role = if link.role == "mentioned", do: " (mentioned)", else: ""
          note = if link.note, do: " — #{escape(link.note)}", else: ""

          "        <li>#{escape(Playcode.Places.breadcrumb(link.place, gazetteer, "es"))}#{role}#{note}</li>"
        end)

      """
            <div class="places">
              <p class="places-label">Places</p>
              <ul>
      #{items}
              </ul>
            </div>
      """
    end)
  end

  defp render_places(_play), do: ""

  defp render_verse_info(play) do
    cond do
      play.verse_count && play.is_verse ->
        "      <p class=\"verse-info\">#{play.verse_count} verses</p>"

      play.verse_count ->
        "      <p class=\"verse-info\">Prose</p>"

      true ->
        ""
    end
  end

  defp render_editorial_notes(notes) do
    notes
    |> Enum.map(fn note ->
      heading = if note.heading, do: "      <h3>#{escape(note.heading)}</h3>\n", else: ""

      "    <div class=\"editorial-note\">\n#{heading}      <div>#{escape(note.content)}</div>\n    </div>"
    end)
    |> Enum.join("\n    <hr class=\"editorial-note-sep\">\n")
  end

  defp render_inline_cast_list(characters) do
    visible = Enum.reject(characters, & &1.is_hidden)
    if visible == [], do: "", else: do_render_inline_cast_list(visible)
  end

  defp do_render_inline_cast_list(characters) do
    items =
      Enum.map(characters, fn char ->
        desc =
          if char.description,
            do: " <span class=\"cast-desc\">#{escape(char.description)}</span>",
            else: ""

        "          <div class=\"cast-item\"><span class=\"cast-name\">#{escape(char.name)}</span>#{desc}</div>"
      end)
      |> Enum.join("\n")

    """
          <div class="cast-list">
    #{items}
          </div>
    """
  end

  defp render_division_nav(divisions) do
    nav_items =
      divisions
      |> Enum.filter(fn div -> div.type in @act_types end)
      |> Enum.map(fn div ->
        act_link = "<a href=\"#div-#{div.id}\">#{escape(div.title || div.type)}</a>"

        scene_links =
          Map.get(div, :children, [])
          |> Enum.filter(fn child -> child.title && child.title != "" end)
          |> Enum.map(fn child ->
            "<a href=\"#div-#{child.id}\">#{escape(child.title)}</a>"
          end)

        case scene_links do
          [] ->
            "        <div class=\"division-nav-group\">#{act_link}</div>"

          links ->
            "        <div class=\"division-nav-group\">#{act_link} <span class=\"scene-links\">(#{Enum.join(links, ", ")})</span></div>"
        end
      end)

    case nav_items do
      [] -> ""
      items -> "      <nav class=\"division-nav\">\n#{Enum.join(items, "\n")}\n      </nav>"
    end
  end

  defp render_divisions(divisions, characters) do
    Enum.map(divisions, fn div ->
      heading = division_heading(div)

      cast =
        if div.type == "elenco",
          do: render_inline_cast_list(characters),
          else: ""

      elements = render_elements(Map.get(div, :loaded_elements, []))

      children =
        Map.get(div, :children, [])
        |> Enum.map(fn child ->
          ch = child_heading(child)
          ce = render_elements(Map.get(child, :loaded_elements, []))
          "      <div class=\"child-division\">\n#{ch}#{ce}      </div>"
        end)
        |> Enum.join("\n")

      "    <div class=\"division\">\n#{heading}#{cast}#{elements}#{children}\n    </div>"
    end)
    |> Enum.join("\n")
  end

  defp division_heading(%{title: nil}), do: ""
  defp division_heading(%{title: ""}), do: ""

  defp division_heading(%{id: id, title: title, type: type}) when type in @act_types do
    "      <h2 id=\"div-#{id}\" class=\"act-heading\">#{escape(title)}</h2>\n"
  end

  defp division_heading(%{id: id, title: title}) do
    "      <h3 id=\"div-#{id}\" class=\"scene-heading\">#{escape(title)}</h3>\n"
  end

  defp child_heading(%{title: nil}), do: ""
  defp child_heading(%{title: ""}), do: ""

  defp child_heading(%{id: id, title: title}),
    do: "        <h3 id=\"div-#{id}\" class=\"scene-heading\">#{escape(title)}</h3>\n"

  defp render_elements(elements) do
    Enum.map(elements, &render_element/1) |> Enum.join()
  end

  defp render_element(%{type: "speech"} = el) do
    aside_class = if el.is_aside, do: " aside", else: ""

    speaker =
      if el.speaker_label,
        do: "        <div class=\"speaker\">#{escape(el.speaker_label)}</div>\n",
        else: ""

    children = Map.get(el, :children, []) |> Enum.map(&render_element/1) |> Enum.join()
    "      <div class=\"speech#{aside_class}\">\n#{speaker}#{children}      </div>\n"
  end

  defp render_element(%{type: "line_group"} = el) do
    Map.get(el, :children, []) |> Enum.map(&render_element/1) |> Enum.join()
  end

  defp render_element(%{type: "verse_line"} = el) do
    content_class =
      cond do
        el.rend == "indent" -> "content indent"
        el.part == "F" -> "content part-f"
        el.part == "M" -> "content part-m"
        true -> "content"
      end

    line_num =
      if el.line_number,
        do: "<span class=\"line-number\">#{el.line_number}</span>",
        else: "<span class=\"line-number\"></span>"

    "        <div class=\"verse-line\"><span class=\"#{content_class}\">#{escape(el.content || "")}</span>#{line_num}</div>\n"
  end

  defp render_element(%{type: "stage_direction"} = el) do
    "        <div class=\"stage-direction\">(#{escape(el.content || "")})</div>\n"
  end

  defp render_element(%{type: "prose"} = el) do
    "        <div class=\"prose-block\">#{escape(el.content || "")}</div>\n"
  end

  defp render_element(_), do: ""

  # --- Characters table ---

  defp render_characters_table(characters) do
    visible = Enum.reject(characters, & &1.is_hidden)

    if visible == [] do
      "      <p style=\"text-align:center;color:#888;\">No characters defined.</p>"
    else
      rows =
        Enum.map(visible, fn char ->
          desc = escape(char.description || "")

          """
                <tr>
                  <td class="char-id">#{escape(char.xml_id || "")}</td>
                  <td><strong>#{escape(char.name)}</strong></td>
                  <td>#{desc}</td>
                </tr>
          """
        end)
        |> Enum.join()

      """
            <table class="characters-table">
              <thead>
                <tr><th>ID</th><th>Name</th><th>Description</th></tr>
              </thead>
              <tbody>
      #{rows}          </tbody>
            </table>
      """
    end
  end

  # --- Statistics rendering ---

  defp render_statistics(nil),
    do: "      <p style=\"text-align:center;color:#888;\">No statistics available.</p>"

  defp render_statistics(%{data: data}) when data == %{} or is_nil(data) do
    "      <p style=\"text-align:center;color:#888;\">No statistics available.</p>"
  end

  defp render_statistics(statistic) do
    data = statistic.data
    raw_label = data["act_label"] || "act"

    summary_cards =
      render_stat_cards([
        {act_label_plural(raw_label), data["num_acts"]},
        {"Scenes", get_in(data, ["scenes", "total"])},
        {"Verses", data["total_verses"]},
        {"Stage Directions", data["total_stage_directions"]},
        {"Split Verses", data["split_verses"]},
        {"Asides", data["total_asides"]}
      ])

    scenes_chart =
      if (get_in(data, ["scenes", "total"]) || 0) > 0 do
        render_bar_chart(
          "Scenes per #{act_label_singular(raw_label)}",
          get_in(data, ["scenes", "per_act"]) || [],
          "act",
          "count",
          "#{act_label_singular(raw_label)} ",
          "bar-amber"
        )
      else
        ""
      end

    verse_chart =
      render_bar_chart(
        "Verse Distribution",
        data["verse_distribution"] || [],
        "act",
        "count",
        "#{act_label_singular(raw_label)} ",
        "bar-indigo"
      )

    prose_chart =
      if (data["total_prose_fragments"] || 0) > 0 do
        render_bar_chart(
          "Prose Fragments",
          data["prose_fragments"] || [],
          "act",
          "count",
          "#{act_label_singular(raw_label)} ",
          "bar-emerald"
        )
      else
        ""
      end

    verse_type_chart =
      case data["verse_type_distribution"] do
        nil ->
          ""

        [] ->
          ""

        items ->
          render_bar_chart(
            "Verse Type Distribution",
            Enum.map(items, fn vt ->
              %{"label" => verse_type_label(vt["verse_type"]), "count" => vt["count"]}
            end),
            "label",
            "count",
            "",
            "bar-violet"
          )
      end

    char_chart =
      case data["character_appearances"] do
        nil ->
          ""

        [] ->
          ""

        items ->
          render_bar_chart(
            "Character Speeches",
            Enum.map(items, fn c -> %{"label" => c["name"], "count" => c["speeches"]} end),
            "label",
            "count",
            "",
            "bar-amber"
          )
      end

    """
          #{summary_cards}
          #{scenes_chart}
          #{verse_chart}
          #{prose_chart}
          #{verse_type_chart}
          #{char_chart}
    """
  end

  defp render_stat_cards(cards) do
    items =
      Enum.map(cards, fn {label, value} ->
        """
              <div class="stat-card">
                <div class="value">#{value || 0}</div>
                <div class="label">#{escape(label)}</div>
              </div>
        """
      end)
      |> Enum.join()

    """
          <div class="stats-cards">
    #{items}        </div>
    """
  end

  defp render_bar_chart(_title, [], _label_key, _value_key, _prefix, _color), do: ""

  defp render_bar_chart(title, items, label_key, value_key, prefix, color_class) do
    max_val = items |> Enum.map(&(&1[value_key] || 0)) |> Enum.max(fn -> 1 end)

    rows =
      Enum.map(items, fn item ->
        val = item[value_key] || 0
        pct = bar_percent(val, max_val)

        """
              <div class="bar-row">
                <span class="bar-label">#{escape(prefix)}#{escape(to_string(item[label_key] || ""))}</span>
                <div class="bar-track">
                  <div class="bar-fill #{color_class}" style="width: #{pct}%"><span>#{val}</span></div>
                </div>
              </div>
        """
      end)
      |> Enum.join()

    """
          <div class="chart-section">
            <h3>#{escape(title)}</h3>
    #{rows}        </div>
    """
  end

  defp bar_percent(0, _max), do: 0
  defp bar_percent(_val, 0), do: 0
  defp bar_percent(val, max), do: (val / max * 100) |> round() |> min(100) |> max(5)

  # --- Statistics label helpers ---

  defp act_label_singular("acto"), do: "Acto"
  defp act_label_singular("jornada"), do: "Jornada"
  defp act_label_singular("act"), do: "Act"
  defp act_label_singular("acte"), do: "Acte"
  defp act_label_singular("play"), do: "Play"
  defp act_label_singular("Jornada"), do: "Jornada"
  defp act_label_singular("Act"), do: "Act"
  defp act_label_singular(other), do: other

  defp act_label_plural("acto"), do: "Actos"
  defp act_label_plural("jornada"), do: "Jornadas"
  defp act_label_plural("act"), do: "Acts"
  defp act_label_plural("acte"), do: "Actes"
  defp act_label_plural("play"), do: "Plays"
  defp act_label_plural("Jornada"), do: "Jornadas"
  defp act_label_plural("Act"), do: "Acts"
  defp act_label_plural(other), do: other <> "s"

  defp verse_type_label("redondilla"), do: "Redondilla"
  defp verse_type_label("romance"), do: "Romance"
  defp verse_type_label("romance_tirada"), do: "Romance (tirada)"
  defp verse_type_label("octava_real"), do: "Octava real"
  defp verse_type_label("soneto"), do: "Soneto"
  defp verse_type_label("decima"), do: "Décima"
  defp verse_type_label("terceto"), do: "Terceto"
  defp verse_type_label("silva"), do: "Silva"
  defp verse_type_label("quintilla"), do: "Quintilla"
  defp verse_type_label("lira"), do: "Lira"
  defp verse_type_label("cancion"), do: "Canción"
  defp verse_type_label("otro"), do: "Otro"
  defp verse_type_label(other), do: other

  # --- Footer ---

  defp footer(version, build_date) do
    """
      <footer class="site-footer">
        <p>EMOTHE Digital Library v#{escape(version)} — Built #{escape(build_date)}</p>
        <p>Source data: TEI-XML files are included alongside each play.</p>
        <p>Generated following <a href="https://endings.uvic.ca/principles.html" style="color:#8b7355;">Endings Project Principles</a>.</p>
      </footer>
    """
  end

  # --- HTML escaping ---

  def escape(nil), do: ""

  def escape(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  def escape(other), do: escape(to_string(other))

  defp escape_attr(text), do: escape(text)
end
