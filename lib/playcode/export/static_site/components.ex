defmodule Playcode.Export.StaticSite.Components do
  @moduledoc """
  The pieces the static site's pages are built from. Plain semantic HTML: the classes
  belong to `priv/static_site/style.css`, and the `data-*` attributes are the hooks
  `site.js` and `search.js` enhance.
  """
  use Phoenix.Component
  use Gettext, backend: PlaycodeWeb.Gettext

  import Playcode.Export.StaticSite.Bilingual

  alias Playcode.Bibliography.Citation
  alias Playcode.Catalogue.{Paratext, Play}
  alias Playcode.Export.NoteMarkup
  alias Playcode.Export.StaticSite.{Edition, Search}
  alias Playcode.Performances
  alias Playcode.PlayContent.{CastListEntry, Division, Element, InlineMarkup, Note}
  alias Playcode.Witnesses
  alias PlaycodeWeb.PlayLabels

  attr :root, :string,
    required: true,
    doc: ~s(path from the page to the site root: "" or "../../")

  attr :title, :any, required: true, doc: "a string, or `{spanish, english}` (`tp/2`)"
  attr :site, :map, required: true
  attr :current, :atom, default: nil

  attr :play, :any,
    default: nil,
    doc: "the play shown, or the plays, whose licences the footer states"

  attr :rail_label, :any, default: nil
  slot :rail
  slot :inner_block, required: true

  def shell(assigns) do
    {title, english} = with title when is_binary(title) <- assigns.title, do: same(title)

    assigns =
      assign(assigns,
        title: title,
        english_title: if(english != title, do: english),
        rail_label: assigns.rail_label || t("Contents & tools")
      )

    ~H"""
    <!DOCTYPE html>
    <html lang="es" data-ui="es">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title data-tr={@english_title && true} data-en-text={@english_title}>{@title}</title>
        <%!-- Not stamped like the links below: it must match style.css's url(), or the font is fetched twice. --%>
        <link
          rel="preload"
          href={@root <> "assets/fonts/source-serif-4-400-latin.woff2"}
          as="font"
          type="font/woff2"
          crossorigin
        />
        <%!-- The reader's light or dark, else the system's, and their interface language,
              before anything paints; without JavaScript the page is light and Spanish. --%>
        <script>
          (function(){var d=document.documentElement,t,u;try{t=localStorage.getItem("reader.theme");u=localStorage.getItem("reader.ui")}catch(e){}d.dataset.theme=t||(matchMedia("(prefers-color-scheme: dark)").matches?"dark":"light");if(u)d.lang=d.dataset.ui=u})()
        </script>
        <link rel="stylesheet" href={@root <> "assets/style.css?v=" <> @site.assets} />
        <script src={@root <> "assets/site.js?v=" <> @site.assets} defer>
        </script>
      </head>
      <body data-ln="5" data-fo="off" data-rs="off" data-sh="off" data-sdm="off">
        <header class="bar">
          <a class="skip" href="#main">{t("Skip to content")}</a>
          <a class="wordmark" href={@root <> "index.html"}>
            EMOTHE<small>{t("Digital library")}</small>
          </a>
          <nav {ta("aria-label", "Site")} class="site">
            <a href={@root <> "index.html"} aria-current={@current == :catalogue && "page"}>
              {t("Catalogue")}
            </a>
            <a href={@root <> "search.html"} aria-current={@current == :search && "page"}>
              {t("Search")}
            </a>
            <a href={@root <> "about.html"} aria-current={@current == :about && "page"}>
              {t("About")}
            </a>
          </nav>
          <%!-- The portal the site belongs to: the one place a page leaves the archive. --%>
          <nav {ta("aria-label", "EMOTHE portal")} class="portal">
            <a href="https://emothe.uv.es/">Portal</a>
            <a href="https://emothe.uv.es/basededatos/">{t("Database")}</a>
          </nav>
          <%!-- Each language named in itself: the one this button switches to. --%>
          <button type="button" class="ui" data-ui-toggle hidden>
            <x-es lang="en">English</x-es>
            <x-en lang="es">Español</x-en>
          </button>
          <button type="button" class="theme" data-theme-toggle {ta("aria-label", "Dark mode")} hidden>
            ◐
          </button>
        </header>
        <div class={["frame", @rail != [] && "with-rail"]}>
          <details :if={@rail != []} class="rail" open>
            <summary>{@rail_label}</summary>
            {render_slot(@rail)}
          </details>
          <main id="main">{render_slot(@inner_block)}</main>
        </div>
        <footer class="foot">
          <p :for={play <- licensed(@play)}>
            <.licence play={play} />
          </p>
          <p>
            {t("EMOTHE · version %{version} · built %{date}",
              version: @site.version,
              date: @site.build_date
            )}
          </p>
          <p>
            {t("A static edition following the")}
            <a href="https://endings.uvic.ca/principles.html">{t("Endings principles")}</a>{t(
              "; every play's TEI-XML source is published beside it."
            )}
          </p>
        </footer>
      </body>
    </html>
    """
  end

  attr :play, :map, required: true

  @doc "The play's licence: its text, linked to its URL when that is a web address."
  def licence(assigns) do
    ~H"""
    {@play.licence_text}
    <%= if web_url?(@play.licence_url) do %>
      <a href={@play.licence_url}>{@play.licence_url}</a>
    <% else %>
      {@play.licence_url}
    <% end %>
    """
  end

  attr :for, :string, required: true, doc: "the toggle that shows it"
  attr :targets, :string, required: true
  attr :previous, :list, required: true, doc: "the back arrow's name, `ta/2`'s attributes"
  attr :next, :list, required: true

  # The arrows and the count site.js's EMOTHE.stepper runs; shown while its toggle is on.
  defp stepper(assigns) do
    ~H"""
    <div class="stepper" data-stepper={@targets} data-for={@for}>
      <button type="button" data-step="-1" {@previous}>‹</button>
      <span data-step-count></span>
      <span class="sr-only" data-step-said aria-live="polite"></span>
      <button type="button" data-step="1" {@next}>›</button>
    </div>
    """
  end

  # A comparison shows two plays, often under one licence: each licence once.
  defp licensed(plays) do
    plays
    |> List.wrap()
    |> Enum.filter(&licence?/1)
    |> Enum.uniq_by(&{&1.licence_text, &1.licence_url})
  end

  def licence?(play), do: play.licence_text not in [nil, ""] or play.licence_url not in [nil, ""]

  defp web_url?(url), do: is_binary(url) and String.starts_with?(url, ["http://", "https://"])

  attr :edition, :map, required: true
  attr :current, :string, required: true
  attr :tools, :boolean, default: false

  attr :page, :map,
    default: nil,
    doc: "the division page, whose text the Highlight switches step through"

  def play_rail(assigns) do
    shown = if assigns.page, do: Edition.page_divisions(assigns.page), else: []

    assigns =
      assign(assigns,
        cast: Enum.filter(cast(assigns.edition.characters), & &1.xml_id),
        shared: Element.shared_lines?(shown),
        stage: Element.stage_directions?(shown)
      )

    ~H"""
    <nav {ta("aria-label", "Contents")}>
      <h2>{t("Contents")}</h2>
      <.play_contents edition={@edition} current={@current} />
    </nav>
    <.play_tools
      :if={@tools}
      variants={@edition.variants}
      folio={@edition.folio}
      tagged={@edition.tagged}
      cast={@cast}
      shared={@shared}
      stage={@stage}
    />
    """
  end

  attr :variants, :boolean, required: true
  attr :folio, :boolean, required: true
  attr :tagged, :boolean, required: true
  attr :cast, :list, required: true, doc: "the characters the Highlight select offers"
  attr :shared, :boolean, required: true
  attr :stage, :boolean, required: true
  attr :steppers, :boolean, default: true, doc: "the arrows, which walk one column"

  @doc "The reading tools: line numbers, the Show switches and the Highlight group."
  def play_tools(assigns) do
    ~H"""
    <div class="tools" data-tools hidden>
      <h2>{t("Line numbers")}</h2>
      <div class="seg" role="group" {ta("aria-label", "Line numbers")}>
        <button type="button" data-ln-set="all">{t("All")}</button>
        <button type="button" data-ln-set="5">5</button>
        <button type="button" data-ln-set="off">{t("Off")}</button>
      </div>
      <h2>{t("Show")}</h2>
      <label><input type="checkbox" data-toggle="sd" checked /> {t("Stage directions")}</label>
      <label><input type="checkbox" data-toggle="vf" checked /> {t("Verse forms")}</label>
      <label :if={@variants}>
        <input type="checkbox" data-toggle="va" checked /> {t("Variants")}
      </label>
      <label :if={@folio}>
        <input type="checkbox" data-toggle="fo" /> {t("Folio interpolations")}
      </label>
      <label :if={@tagged}>
        <input type="checkbox" data-toggle="rs" /> {t("Tagged names")}
      </label>
      <%= if @cast != [] or @shared or @stage do %>
        <h2>{t("Highlight")}</h2>
        <select :if={@cast != []} data-highlight {ta("aria-label", "Highlight a character")}>
          <option value="" {ta("label", "No one")}></option>
          <option :for={character <- @cast} value={character.xml_id}>
            {InlineMarkup.plain(character.name)}
          </option>
        </select>
        <%= if @shared do %>
          <label><input type="checkbox" data-toggle="sh" /> {t("Shared lines")}</label>
          <.stepper
            :if={@steppers}
            for="sh"
            targets=".text .l[data-part=I]"
            previous={ta("aria-label", "Previous shared line")}
            next={ta("aria-label", "Next shared line")}
          />
          <ul class="shared-legend">
            <li :for={
              {part, label} <- [
                {"I", t("First part")},
                {"M", t("Middle part")},
                {"F", t("Last part")}
              ]
            }>
              <i class="sw" data-part={part}></i>{label}
            </li>
          </ul>
        <% end %>
        <%= if @stage do %>
          <label>
            <input type="checkbox" data-toggle="sdm" {ta("aria-label", "Highlight stage directions")} />
            {t("Stage directions")}
          </label>
          <.stepper
            :if={@steppers}
            for="sdm"
            targets=".text .sd, .text .sdi"
            previous={ta("aria-label", "Previous stage direction")}
            next={ta("aria-label", "Next stage direction")}
          />
        <% end %>
      <% end %>
    </div>
    """
  end

  attr :edition, :map, required: true
  attr :current, :string, default: nil
  attr :all_scenes, :boolean, default: false

  def play_contents(assigns) do
    ~H"""
    <ul>
      <li><a href="index.html" aria-current={@current == "index" && "page"}>{t("Title page")}</a></li>
      <%= for entry <- @edition.contents do %>
        <%= case entry do %>
          <% {:item, item} -> %>
            <li><a href={item_href(@edition, item)}>{item_title(item)}</a></li>
          <% {:page, page} -> %>
            <li>
              <a href={page.slug <> ".html"} aria-current={@current == page.slug && "page"}>
                {page.title}
              </a>
              <ul :if={
                (@all_scenes or open?(@edition, page, @current)) and page.division.children != []
              }>
                <li :for={{child, n} <- numbered_children(page.division)}>
                  <%= cond do %>
                    <% n == nil -> %>
                      <a href={item_href(@edition, child)}>{item_title(child)}</a>
                    <% scene_page = Edition.scene_page(@edition, child) -> %>
                      <a
                        href={scene_page.slug <> ".html"}
                        aria-current={@current == scene_page.slug && "page"}
                      >
                        {Edition.scene_title(child, n)}
                      </a>
                    <% true -> %>
                      <a href={"#{page.slug}.html##{@edition.anchors[child.id]}"}>
                        {Edition.scene_title(child, n)}
                      </a>
                  <% end %>
                </li>
              </ul>
            </li>
        <% end %>
      <% end %>
      <li><a href="text.html" aria-current={@current == "text" && "page"}>{t("Full text")}</a></li>
      <li>
        <a href="statistics.html" aria-current={@current == "statistics" && "page"}>
          {t("Statistics")}
        </a>
      </li>
      <li :if={@edition.notes != []}>
        <a href="notes.html" aria-current={@current == "notes" && "page"}>{t("Notes")}</a>
      </li>
      <li :if={@edition.stage_directions != []}>
        <a href="stage-directions.html" aria-current={@current == "stage-directions" && "page"}>
          {t("Stage directions")}
        </a>
      </li>
      <li :if={@edition.play.edition_notes != []}>
        <a href="index.html#edition-notes">{t("Notes on the edition")}</a>
      </li>
      <li :if={@edition.play.witnesses != []}>
        <a href="index.html#witnesses">{t("Witnesses")}</a>
      </li>
      <li :if={@edition.performances != []}>
        <a href="index.html#performances">{t("Performances")}</a>
      </li>
      <li :if={@edition.bibliography != []}>
        <a href="index.html#bibliography">{t("Bibliography")}</a>
      </li>
    </ul>
    """
  end

  # A division's children for the Contents: each scene with its number, a cast list with nil.
  defp numbered_children(division) do
    numbers = Map.new(Division.numbered_scenes(division), fn {scene, n} -> {scene.id, n} end)
    Enum.map(division.children, &{&1, numbers[&1.id]})
  end

  # Where a paratext or a cast list prints after the title page, and what it is called there.
  defp item_href(edition, item),
    do: "#{edition.item_pages[item.id]}.html##{edition.anchors[item.id]}"

  defp item_title(%Paratext{} = paratext), do: both(fn -> PlayLabels.paratext_title(paratext) end)
  defp item_title(list), do: list_title(list)

  defp list_title(%{title: title}) when title not in [nil, ""], do: InlineMarkup.plain(title)
  defp list_title(_list), do: "Dramatis personae"

  # A division's scenes show in the rail on its page and on its scene pages.
  defp open?(edition, page, current) do
    current == page.slug or
      Enum.any?(
        edition.pages,
        &(&1.scene != nil and &1.division.id == page.division.id and &1.slug == current)
      )
  end

  attr :play, :map, required: true

  def study(assigns) do
    ~H"""
    <%= if @play.historical_time do %>
      <dt>{t("Historical time")}</dt>
      <dd>
        {both(fn -> PlayLabels.historical_time_label(@play.historical_time) end)}
        <span :if={@play.historical_time_note} class="note">{@play.historical_time_note}</span>
      </dd>
    <% end %>
    <%= if @play.composition_date_from || @play.composition_date_note do %>
      <dt>{t("Composition")}</dt>
      <dd>
        {Play.composition_years(@play)}
        <span :if={@play.composition_date_note} class="note">{@play.composition_date_note}</span>
      </dd>
    <% end %>
    """
  end

  attr :play, :map, required: true
  attr :published, :any, required: true

  def family(assigns) do
    published? = &(&1 && MapSet.member?(assigns.published, &1.code))

    # A play linked with no kind (FileMaker linked a few) names no relation, as the play
    # page does: "Original of" would be false.
    named? = kind(assigns.play) != "original"

    assigns =
      assign(assigns,
        original:
          if(named? and published?.(assigns.play.parent_play), do: assigns.play.parent_play),
        derived: Enum.filter(assigns.play.derived_plays, published?)
      )

    ~H"""
    <section :if={@original || @derived != []}>
      <h2>{t("Work family")}</h2>
      <p :if={@original}>
        {relation(@play)}
        <a href={"../#{@original.code}/index.html"}><cite>{@original.title}</cite></a>
      </p>
      <ul :if={@derived != []}>
        <li :for={play <- @derived}>
          <a href={"../#{play.code}/index.html"}><cite>{play.title}</cite></a>
          <span class="role">{html(family_role(play))}</span>
        </li>
      </ul>
    </section>
    """
  end

  attr :play, :map, required: true

  # The notes on the edition (question 26), a witness list whole.
  def edition_notes(assigns) do
    ~H"""
    <section :if={@play.edition_notes != []} id="edition-notes">
      <h2>{t("Notes on the edition")}</h2>
      <p :for={note <- @play.edition_notes}><.inline text={note} /></p>
    </section>
    """
  end

  attr :play, :map, required: true

  # The bibliography's class gives the hanging indent; no CSS of its own.
  def witnesses(assigns) do
    ~H"""
    <section :if={@play.witnesses != []} id="witnesses" class="bibliography">
      <h2>{t("Witnesses")}</h2>
      <ul>
        <li :for={witness <- @play.witnesses}>{Witnesses.html(witness)}</li>
      </ul>
    </section>
    """
  end

  attr :edition, :map, required: true

  # Layout B: a line each, the sources they cite once below. Its place names are in
  # Spanish, as the Places section's.
  def performances(assigns) do
    assigns = assign(assigns, :listing, performance_listing(assigns.edition))

    ~H"""
    <section :if={@listing.lines != []} id="performances" class="performances">
      <h2>{t("Performances")}</h2>
      <ul>
        <li :for={line <- @listing.lines} class="performance">
          <b :if={line.date}><.inline text={line.date} /></b>
          <%= case line.parts do %>
            <% {same, same} -> %>
              <.inline text={same} />
            <% {es, en} -> %>
              <x-es><.inline text={es} /></x-es>
              <x-en><.inline text={en} /></x-en>
          <% end %>
          <span :if={line.reference} class="note">
            {line.reference}
          </span>
          <p :if={line.cast != []} class="note">
            {t("Cast:")} <.inline text={Enum.join(line.cast, "; ")} />
          </p>
          <p :if={line.note} class="note"><.inline text={line.note} /></p>
        </li>
      </ul>
      <ul :if={@listing.sources != []} class="sources">
        <li :for={{number, entry} <- @listing.sources}>[{number}] {Citation.html(entry)}</li>
      </ul>
    </section>
    """
  end

  # The gazetteer is loaded only for a performance that has a place, as `place_links/1` does.
  # Its venue types are in both languages, so each line's parts are `{spanish, english}`.
  defp performance_listing(%{performances: performances, characters: characters}) do
    gazetteer = if Enum.any?(performances, & &1.place), do: Playcode.Places.gazetteer(), else: %{}
    listing = Performances.listing(performances, characters, gazetteer, {"es", "en"}, "es")

    lines =
      for %{parts: {es, en}} = line <- listing.lines,
          do: %{line | parts: {Enum.join(es, " · "), Enum.join(en, " · ")}}

    %{listing | lines: lines}
  end

  attr :groups, :list, required: true

  def bibliography(assigns) do
    ~H"""
    <section :if={@groups != []} id="bibliography" class="bibliography">
      <h2>{t("Bibliography")}</h2>
      <%= for {kind, subgroups} <- @groups do %>
        <h3>{both(fn -> PlayLabels.bibliography_kind_label(kind) end)}</h3>
        <%= for {language, links} <- subgroups do %>
          <h4 :if={kind == "translation"}>
            {if language,
              do: html(language(language)),
              else: both(fn -> PlayLabels.bibliography_language_label(nil) end)}
          </h4>
          <ul>
            <li :for={link <- links}>{Citation.html(link.entry, link)}</li>
          </ul>
        <% end %>
      <% end %>
    </section>
    """
  end

  attr :play, :map, required: true

  def places(assigns) do
    assigns = assign(assigns, :links, place_links(assigns.play))

    ~H"""
    <section :if={@links != []}>
      <h2>{t("Places")}</h2>
      <ul>
        <li :for={{name, mentioned?, note} <- @links}>
          {name}<span :if={mentioned?} class="role"> ({t("mentioned")})</span>
          <span :if={note}>
            — {note}
          </span>
        </li>
      </ul>
    </section>
    """
  end

  defp place_links(%{play_places: [_ | _] = links}) do
    gazetteer = Playcode.Places.gazetteer()

    links
    |> Enum.sort_by(&{&1.role != "setting", &1.position})
    |> Enum.map(
      &{Playcode.Places.place_line(&1, gazetteer, "es"), &1.role == "mentioned", &1.note}
    )
  end

  defp place_links(_play), do: []

  @doc "The cast as published: every character not marked hidden."
  def cast(characters), do: Enum.reject(characters, & &1.is_hidden)

  attr :edition, :map, required: true
  attr :item, :map, required: true
  attr :head, :string, default: nil, doc: "the heading's class: `act-head` among the acts"

  @doc """
  A paratext or a cast list where the outline puts it (`Edition`): on the title page,
  above a page's heading, among an act's scenes, or after the text.
  """
  def outline_item(%{item: %Paratext{}} = assigns) do
    ~H"""
    <section id={@edition.anchors[@item.id]}>
      <%= if Paratext.scene?(@item.kind) do %>
        <h3 :if={@item.heading}><.inline text={@item.heading} /></h3>
      <% else %>
        <h2 :if={@item.heading} class={@head}><.inline text={@item.heading} /></h2>
        <h2 :if={!@item.heading} class={@head}>
          {both(fn -> PlayLabels.kind_label(@item.kind) end)}
        </h2>
      <% end %>
      <p :for={paragraph <- paragraphs(@item.content)}><.inline text={paragraph} /></p>
      <p :if={@item.trailer} class="tr"><.inline text={@item.trailer} /></p>
      <p :for={paragraph <- paragraphs(@item.note)}><.inline text={paragraph} /></p>
    </section>
    """
  end

  def outline_item(%{item: %{parent_id: nil}} = assigns) do
    ~H"""
    <section id={@edition.anchors[@item.id]}>
      <h2 class={@head}>
        <.inline text={@item.title || "Dramatis personae"} notes={@item.notes} />
      </h2>
      <.cast_entries list={@item} />
    </section>
    """
  end

  def outline_item(assigns) do
    ~H"""
    <section id={@edition.anchors[@item.id]}>
      <h3 :if={@item.title} class="scene-head">
        <.inline text={@item.title} notes={@item.notes} />
      </h3>
      <.cast_entries list={@item} />
    </section>
    """
  end

  attr :list, :map, required: true

  # A cast list's own entries, a group's under its heading; the line introducing it before
  # them and its note after.
  defp cast_entries(assigns) do
    ~H"""
    <p :for={paragraph <- paragraphs(@list.intro)}><.inline text={paragraph} /></p>
    <%= for [first | _] = group <- CastListEntry.printed_groups(@list.entries) do %>
      <p :if={first.group_heading} class="cast-group"><.inline text={first.group_heading} /></p>
      <dl class="cast">
        <%= for entry <- group do %>
          <dt><.inline text={entry.name} /></dt>
          <dd><.inline text={entry.description} /></dd>
        <% end %>
      </dl>
    <% end %>
    <p :for={paragraph <- paragraphs(@list.note)} class="cast-note"><.inline text={paragraph} /></p>
    """
  end

  @doc "What the title page says about the play's form."
  def form_summary(play, stats) do
    verses = stats["verses"] || 0

    case {Play.form(play), verses} do
      {"prose", _} -> t("Prose")
      {"occasional_verse", _} -> t("Prose with occasional verse")
      {"verse", n} when n > 0 -> t("Verse · %{n} verses", n: number(n))
      {"verse", _} -> t("Verse")
      {"mixed", n} when n > 0 -> t("Verse and prose · %{n} verses", n: number(n))
      {"mixed", _} -> t("Verse and prose")
    end
  end

  @doc """
  An integer as both languages can read it: from five digits, its thousands apart by a
  narrow space ("12 345"), not the English comma, which a Spanish reader takes for a
  decimal point; four digits stay whole, as Spanish writes them ("2345").
  """
  def number(nil), do: "0"

  def number(n) when is_integer(n) and n >= 10_000,
    do: n |> Integer.to_string() |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, "\u202F")

  def number(n) when is_integer(n), do: Integer.to_string(n)

  def source_text(source) do
    [
      source.author,
      source.title,
      source.editor,
      source.pub_place,
      source.publisher,
      source.pub_date,
      source.note
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.reduce("", &sentence/2)
  end

  # Each part a sentence of its own, without a second period after one it ends with
  # ("…Paris, 1872. Tasso, Torquato. Aminta.").
  defp sentence(part, ""), do: part

  defp sentence(part, text),
    do: if(String.ends_with?(text, "."), do: text <> " " <> part, else: text <> ". " <> part)

  def paragraphs(nil), do: []
  def paragraphs(text), do: String.split(text, ~r/\n\s*\n/, trim: true)

  @doc "The citation shown on the title page; JS adds the page's URL when copying."
  def citation(play, site) do
    editors = for e <- play.editors, e.role in ~w(editor critical_editor), do: e.person_name

    both(fn ->
      [
        play.author_name,
        play.title,
        editors != [] && "ed. " <> Enum.join(editors, ", "),
        gettext("EMOTHE, version %{version} (%{year})",
          version: site.version,
          year: String.slice(site.build_date, 0, 4)
        )
      ]
      |> Enum.filter(&(is_binary(&1) and &1 != ""))
      |> Enum.join(". ")
      |> Kernel.<>(".")
    end)
  end

  attr :play, :map, required: true

  def play_header(assigns) do
    ~H"""
    <header class="play-head">
      <p class="author">{@play.author_name}</p>
      <h1><a href="index.html">{@play.title}</a></h1>
    </header>
    """
  end

  attr :prev, :map, default: nil
  attr :next, :map, default: nil

  def pager(assigns) do
    ~H"""
    <nav :if={@prev || @next} class="pager" {ta("aria-label", "Acts")}>
      <a :if={@prev} href={@prev.slug <> ".html"} rel="prev">← {@prev.title}</a>
      <a :if={@next} href={@next.slug <> ".html"} rel="next">{@next.title} →</a>
    </nav>
    """
  end

  @doc "What a copied line link is cited as, before its verse number."
  def cite_prefix(play, page) do
    [play.author_name, play.title, page && page.title]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
  end

  attr :edition, :map, required: true
  attr :notes_label, :any, default: nil
  attr :texts, :map, default: %{}, doc: "`Pages.texts/1`, when the play's pages share it"

  @doc "A play's whole text, as `text.html` shows it: its contents, then its endnotes."
  def full_text(assigns) do
    ~H"""
    <%= for entry <- @edition.contents do %>
      <%= case entry do %>
        <% {:page, page} -> %>
          <.division_text edition={@edition} division={page.division} texts={@texts} />
        <% {:item, item} -> %>
          <.outline_item edition={@edition} item={item} head="act-head" />
      <% end %>
    <% end %>
    <.endnotes
      label={@notes_label}
      notes={
        @edition.pages |> Enum.reject(& &1.scene) |> Enum.map(& &1.division) |> Note.reading_order()
      }
    />
    """
  end

  # A comparison key of the speech or heading `id` (`StaticSite.Comparison`), nil on every
  # page but the comparison's.
  defp sync(%{sync: %{} = sync}, kind, id), do: sync[kind][id]
  defp sync(_edition, _kind, _id), do: nil

  attr :edition, :map, required: true
  attr :division, :map, required: true
  attr :texts, :map, default: %{}

  def division_text(assigns) do
    {opening, rest} = Division.split_opening_lists(assigns.division.children)
    assigns = assign(assigns, opening: opening, rest: rest)

    ~H"""
    <section class="division" id={@edition.anchors[@division.id]}>
      <h2
        :if={@division.title}
        class="act-head"
        data-sync-div={sync(@edition, :div, @division.id)}
      >
        <.inline text={@division.title} notes={@division.notes} />
      </h2>
      <.outline_item :for={list <- @opening} edition={@edition} item={list} />
      <.elements of={@division} edition={@edition} texts={@texts} />
      <%= for child <- @rest do %>
        <%= if child.type == "elenco" do %>
          <.outline_item edition={@edition} item={child} />
        <% else %>
          <section id={@edition.anchors[child.id]}>
            <h3
              :if={child.title}
              class="scene-head"
              data-sync-div={sync(@edition, :div, child.id)}
            >
              <.inline text={child.title} notes={child.notes} />
            </h3>
            <.elements of={child} edition={@edition} texts={@texts} />
          </section>
        <% end %>
      <% end %>
    </section>
    """
  end

  attr :edition, :map, required: true
  attr :page, :map, required: true
  attr :texts, :map, default: %{}

  @doc """
  What one division page shows: the division whole; or, for a division split by scene,
  its own text and a list of its scene pages; or one scene of it.
  """
  def page_text(%{page: %{scene: nil, split: false}} = assigns) do
    ~H"""
    <.division_text edition={@edition} division={@page.division} texts={@texts} />
    """
  end

  def page_text(%{page: %{scene: nil, split: true}} = assigns) do
    {opening, _rest} = Division.split_opening_lists(assigns.page.division.children)

    assigns =
      assign(assigns,
        opening: opening,
        scene_pages:
          Enum.filter(
            assigns.edition.pages,
            &(&1.scene && &1.division.id == assigns.page.division.id)
          )
      )

    ~H"""
    <section class="division" id={@edition.anchors[@page.division.id]}>
      <h2 :if={@page.division.title} class="act-head">
        <.inline text={@page.division.title} notes={@page.division.notes} />
      </h2>
      <.outline_item :for={list <- @opening} edition={@edition} item={list} />
      <.elements of={@page.division} edition={@edition} texts={@texts} />
      <nav aria-label="Scenes">
        <ul>
          <li :for={scene_page <- @scene_pages}>
            <a href={scene_page.slug <> ".html"}>
              {Edition.scene_title(scene_page.scene, scene_page.number)}
            </a>
          </li>
        </ul>
      </nav>
    </section>
    """
  end

  def page_text(assigns) do
    ~H"""
    <section class="division">
      <h2 :if={@page.division.title} class="act-head">
        <.inline text={@page.division.title} notes={@page.division.notes} />
      </h2>
      <.outline_item :for={item <- Edition.before(@edition, @page)} edition={@edition} item={item} />
      <section id={@edition.anchors[@page.scene.id]}>
        <h3 :if={@page.scene.title} class="scene-head">
          <.inline text={@page.scene.title} notes={@page.scene.notes} />
        </h3>
        <.elements of={@page.scene} edition={@edition} texts={@texts} />
      </section>
    </section>
    """
  end

  attr :of, :map, required: true, doc: "a division or a scene"
  attr :edition, :map, required: true
  attr :texts, :map, default: %{}

  @doc """
  A division's or a scene's own elements: as `texts` holds them, rendered once for both
  its page and text.html (`Pages.texts/1`), or rendered here.
  """
  def elements(assigns) do
    case assigns.texts[assigns.of.id] do
      nil ->
        ~H"""
        <.el :for={el <- @of.loaded_elements} el={el} edition={@edition} />
        """

      html ->
        assigns = assign(assigns, :html, html)
        ~H"{@html}"
    end
  end

  attr :el, :map, required: true
  attr :edition, :map, required: true

  defp el(%{el: %{type: "speech"}} = assigns) do
    assigns = assign(assigns, :who, who(assigns.el))

    ~H"""
    <div
      class={["sp", Element.folio_only?(@el) && "fo"]}
      data-who={@who}
      data-sync-act={sync(@edition, :act, @el.id)}
      data-pair={sync(@edition, :pair, @el.id)}
    >
      <p :if={@el.speaker_label} class={["spk", InlineMarkup.whole_folio?(@el.speaker_label) && "fo"]}>
        <.inline text={@el.speaker_label} notes={@el.notes} />
      </p>
      <.el :for={child <- @el.children} el={child} edition={@edition} />
    </div>
    """
  end

  defp el(%{el: %{type: "line_group"}} = assigns) do
    ~H"""
    <div class={["lg", Element.folio_only?(@el) && "fo"]}>
      <p :if={@el.content} class="tr"><.inline text={@el.content} notes={@el.notes} /></p>
      <.el :for={child <- @el.children} el={child} edition={@edition} />
    </div>
    """
  end

  # One line of markup, kept from the formatter by phx-no-format (which HEEx drops from
  # the output): a newline between these spans would be a visible space.
  defp el(%{el: %{type: "verse_line"}} = assigns) do
    edition = assigns.edition

    assigns =
      assign(assigns,
        anchor: edition.anchors[assigns.el.id],
        ghost: edition.ghosts[assigns.el.id],
        form: edition.passage_starts[assigns.el.id],
        aside: MapSet.member?(edition.aside_starts, assigns.el.id)
      )

    ~H"""
    <div
      phx-no-format
      class={[
        "l",
        @el.rend == "indent" && "indent",
        Element.folio_only?(@el) && "fo",
        part_step(@el)
      ]}
      data-part={@el.part}
      id={@anchor}
    ><a :if={@el.line_number} class={["n", fifth?(@el.line_number) && "m5"]} href={"#" <> @anchor}>{@el.line_number}</a><span class="t"><span :if={@ghost} class={["ghost", @ghost.indent && "indent"]} aria-hidden="true"><.inline text={@ghost.lead} /> </span><.inline text={@el.content} notes={@el.notes} /></span><span :if={@form || @aside} class="margin"><span :if={@form} class="vf">{both(fn -> PlayLabels.verse_form_label(@form) end)}</span><span :if={@aside} class="aparte">aparte</span></span></div>
    """
  end

  defp el(%{el: %{type: "stage_direction"}} = assigns) do
    ~H"""
    <p phx-no-format class={["sd", Element.folio_only?(@el) && "fo"]} id={@edition.anchors[@el.id]}><.inline text={@el.content} notes={@el.notes} /></p>
    """
  end

  # A numbered paragraph's own number links to its anchor, as a verse's does, so the cite
  # button (site.js, `a[href^="#l"]`) takes it. Notes stay put: they are placed by
  # grapheme offset, and a number marker has none.
  defp el(%{el: %{type: "prose"}} = assigns) do
    {number, text} = InlineMarkup.paragraph_number(assigns.el.content)

    assigns =
      assign(assigns, number: number, text: text, anchor: assigns.edition.anchors[assigns.el.id])

    ~H"""
    <p phx-no-format class={["pr", Element.folio_only?(@el) && "fo"]} id={@anchor}><a :if={@number} class={["pn", fifth?(@number) && "m5"]} href={"#" <> @anchor}>{@number}</a><.inline text={@text} notes={@el.notes} /></p>
    """
  end

  # An opening formula (the Arte nuevo's dedication) or a closing one, centred alike.
  defp el(%{el: %{type: type}} = assigns) when type in ~w(opener trailer) do
    ~H"""
    <p class="tr" id={@edition.anchors[@el.id]}><.inline text={@el.content} notes={@el.notes} /></p>
    """
  end

  defp el(assigns), do: ~H""

  # Every middle or last part steps in by a fixed indent, as emothe.uv.es printed it;
  # site.js lines a part with an earlier one up after it instead, where the line has room.
  defp part_step(%{part: part}) when part in ["M", "F"], do: "part-" <> String.downcase(part)
  defp part_step(_el), do: nil

  defp who(speech) do
    case for(character <- Element.characters(speech), character.xml_id, do: character.xml_id) do
      [] -> nil
      ids -> Enum.join(ids, " ")
    end
  end

  attr :text, :string, default: nil
  attr :notes, :list, default: []

  @doc """
  Stored text as HTML: italics as `<em>`, each line break a `<br>` (inside the italics
  too: they are read first, so a break cannot leave their markers as text), each
  printed line's number a `span.pn`, and the notes' markers. A paratext's paragraph goes
  through it too.
  """
  def inline(assigns) do
    parts = assigns.text |> InlineMarkup.parts(assigns.notes) |> InlineMarkup.folio_labels()
    assigns = assign(assigns, :parts, parts)

    # Built as iodata, not a template: the formatter indents EEx blocks, and the
    # whitespace it adds between a word and its <em> would be visible.
    ~H"""
    {Phoenix.HTML.raw(Enum.map(@parts, &part/1))}
    """
  end

  # A piece of an inline stage direction, a note's number among them: in a span the
  # "Stage directions" toggle hides.
  defp part(%{stage: %{}} = part),
    do: [~s(<span class="sdi">), part(%{part | stage: nil}), "</span>"]

  # Hamlet's Folio passages: an F where one starts and ends, and its words, in grey; gone
  # while the "Folio interpolations" toggle is off, its default (style.css). Inside a stage
  # direction these come after the stage's own clause, so hiding the stage hides its F's.
  defp part(%{label: label}), do: [~s(<sup class="fo fl">), escape(label), "</sup>"]

  defp part(%{folio: _} = part),
    do: [~s(<span class="fo">), part(Map.delete(part, :folio)), "</span>"]

  # The words an <rs> tags, named by its kind; underlined while the "Tagged names" toggle
  # is on (style.css). A note at their end stays outside: its button is named already.
  # ponytail: a title shows on hover only, not on a tap.
  defp part(%{rs: %{} = rs, text: _} = part) do
    attr =
      case pair(fn -> PlayLabels.tag_type_label(rs.type) end) do
        {nil, _} -> []
        title -> attrs_html(title, "title")
      end

    [~s(<span class="rs"), attr, ">", part(Map.delete(part, :rs)), "</span>"]
  end

  # Where a printed line of the source starts inside a paragraph: its number, which the
  # "Line numbers" control hides (style.css), every fifth kept by "5". Plain text: only the
  # paragraph's own number, at its start, is an anchor and a link (`el/1`).
  defp part(%{number: n}),
    do: [~s(<span class="pn), if(fifth?(n), do: " m5", else: ""), ~s(">), escape(n), "</span>"]

  # A note's marker: its number, a button that opens the note (endnotes/1) as a popover.
  # Its id is what a search result and the Notes page link to. A variant's is an asterisk,
  # which the "Variants" toggle hides.
  defp part(%{note: note}),
    do: if(Note.variant?(note), do: variant_ref(note), else: note_ref(note))

  defp part(%{italic: true, text: text}),
    do: ["<em>", breaks(text), "</em>"]

  defp part(%{text: text}), do: breaks(text)

  defp note_ref(note) do
    number = Integer.to_string(note.number)

    [
      ~s(<button type="button" id="nref-),
      number,
      ~s(" class="nref" popovertarget="note-),
      number,
      ~s("),
      attrs_html(ref_label(note, number), "aria-label"),
      ">",
      number,
      "</button>"
    ]
  end

  defp variant_ref(note) do
    number = Integer.to_string(note.number)

    [
      ~s(<button type="button" class="vref" popovertarget="var-),
      number,
      ~s("),
      attrs_html(ref_label(note, number), "aria-label"),
      ~s(>*</button>)
    ]
  end

  defp ref_label(note, number),
    do: pair(fn -> "#{PlayLabels.note_type_label(note.type)} #{number}" end)

  defp breaks(text), do: text |> escape() |> String.replace("\n", "<br>")

  defp fifth?(n), do: match?({i, ""} when rem(i, 5) == 0, Integer.parse(n))

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  attr :notes, :list, required: true
  attr :label, :list, default: nil, doc: "the notes' name, `ta/2`'s attributes"

  @doc """
  A page's notes. Each is a popover its marker opens (`part/1`); in print, and in a
  browser without popover, they are the page's endnotes, its variants after them.
  """
  def endnotes(assigns) do
    {variants, notes} = Enum.split_with(assigns.notes, &Note.variant?/1)

    assigns =
      assign(assigns,
        notes: notes,
        variants: variants,
        label: assigns.label || ta("aria-label", "Notes")
      )

    ~H"""
    <section :if={@notes != []} class="notes" role="doc-endnotes" {@label}>
      <ol>
        <li :for={note <- @notes} id={"note-#{note.number}"} popover value={note.number}>
          <button
            type="button"
            popovertarget={"note-#{note.number}"}
            popovertargetaction="hide"
            {ta("aria-label", "Close")}
          >
            ×
          </button>
          <b>{both(fn -> PlayLabels.note_type_label(note.type) end)}</b>
          <i :if={note.term}><.inline text={note.term} /></i>
          <p :for={paragraph <- Note.paragraphs(note)}><.inline text={paragraph} /></p>
        </li>
      </ol>
    </section>
    <section :if={@variants != []} class="notes" {ta("aria-label", "Textual variants")}>
      <ul>
        <li :for={variant <- @variants} id={"var-#{variant.number}"} popover>
          <button
            type="button"
            popovertarget={"var-#{variant.number}"}
            popovertargetaction="hide"
            {ta("aria-label", "Close")}
          >
            ×
          </button>
          <b>{both(fn -> PlayLabels.note_type_label(variant.type) end)}</b>
          {Phoenix.HTML.raw(NoteMarkup.readings(variant, :html))}
        </li>
      </ul>
    </section>
    """
  end

  attr :stats, :map, required: true

  def stat_tiles(assigns) do
    s = assigns.stats

    tiles =
      Enum.reject(
        [
          {s["num_acts"], t("acts")},
          {s["scenes"], t("scenes")},
          {s["verses"], t("verses")},
          {s["split_verses"], t("shared verses")},
          {length(s["metrical_passages"] || []), t("metrical passages")},
          {s["total_prose_fragments"], t("prose passages")},
          {s["speeches"], t("speeches")},
          {length(s["characters"] || []), t("speaking characters")},
          {s["total_stage_directions"], t("stage directions")},
          {s["total_asides"], t("asides")},
          {s["aside_verses"], t("verses in asides")}
        ],
        fn {value, _label} -> value in [nil, 0] end
      )

    assigns = assign(assigns, :tiles, tiles)

    ~H"""
    <dl id="tiles" class="tiles">
      <div :for={{value, label} <- @tiles}>
        <dt>{label}</dt>
        <dd>{number(value)}</dd>
      </div>
    </dl>
    """
  end

  attr :rows, :list, required: true

  def division_table(assigns) do
    assigns = assign(assigns, :prose?, Enum.any?(assigns.rows, &(&1["prose"] > 0)))

    ~H"""
    <section :if={length(@rows) > 1} id="divisions">
      <h2>{t("By act and scene")}</h2>
      <table>
        <thead>
          <tr>
            <th>{t("Act or scene")}</th>
            <th class="num">{t("Verses")}</th>
            <th class="num">{t("Speeches")}</th>
            <th class="num">{t("Speaking characters")}</th>
            <th :if={@prose?} class="num">{t("Prose passages")}</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={row <- @rows} class={row["scene"] && "sc"}>
            <th scope="row"><.inline text={row["label"]} /></th>
            <td class="num">{number(row["verses"])}</td>
            <td class="num">{number(row["speeches"])}</td>
            <td class="num">{number(row["speakers"])}</td>
            <td :if={@prose?} class="num">{number(row["prose"])}</td>
          </tr>
        </tbody>
      </table>
    </section>
    """
  end

  # The corpus's three commonest forms, 71% of its verse, keep a colour each and every
  # other form is grey: three colours are as many as the band can tell apart (question 16).
  @coloured_forms %{
    "redondilla" => "f-redondilla",
    "romance" => "f-romance",
    "romance_tirada" => "f-romance",
    "quintilla" => "f-quintilla"
  }

  defp form_colour(form), do: Map.get(@coloured_forms, form, "f-other")

  attr :passages, :list, required: true
  attr :range_label, :string, default: "vv.", doc: "the word a range of numbers is cited with"

  def synopsis(assigns) do
    total = assigns.passages |> Enum.map(& &1["verses"]) |> Enum.sum() |> max(1)

    # By label, so romance and romance_tirada, both "Romance", are one form.
    forms =
      assigns.passages
      |> Enum.group_by(&form_label(&1["form"]))
      |> Enum.map(fn {label, [first | _] = passages} ->
        {html(label), form_colour(first["form"]),
         passages |> Enum.map(& &1["verses"]) |> Enum.sum()}
      end)
      |> Enum.sort_by(&(-elem(&1, 2)))

    assigns =
      assign(assigns,
        segments: segments(assigns.passages, total, assigns.range_label),
        forms: forms,
        total: total
      )

    ~H"""
    <section id="synopsis">
      <h2>{t("Metrical synopsis")}</h2>
      <p class="lede">
        {t("The verse forms in order, each passage drawn to scale. Dashed lines mark the acts.")}
      </p>
      <div
        class="band"
        role="img"
        {ta("aria-label", "Metrical synopsis drawn to scale; the table below lists every passage.")}
      >
        <%= for segment <- @segments do %>
          <span :if={segment.sep} class="sep"></span>
          <span
            class={["pass", segment.colour]}
            style={"flex-grow: #{segment.verses}"}
            {attrs(segment.title, "title")}
          >
            <span :if={segment.label}>{html(segment.label)}</span>
          </span>
        <% end %>
      </div>
      <ul class="legend">
        <li :for={{label, colour, verses} <- @forms}>
          <i class={["sw", colour]}></i><b>{label}</b> {number(verses)} vv. · {percent(
            verses,
            @total
          )}
        </li>
      </ul>
      <table>
        <thead>
          <tr>
            <th>{t("Act")}</th>
            <th>{t("Form")}</th>
            <th>vv.</th>
            <th class="num">{t("Verses")}</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={passage <- @passages}>
            <td>{passage["act"] && Edition.roman(passage["act"])}</td>
            <td>
              <i class={["sw", form_colour(passage["form"])]}></i>{html(form_label(passage["form"]))}
            </td>
            <td>{range(passage)}</td>
            <td class="num">{number(passage["verses"])}</td>
          </tr>
        </tbody>
      </table>
      <p class="note">
        {t(
          "Rhyme is not encoded, so two consecutive romances with different assonance show as one passage."
        )}
      </p>
    </section>
    """
  end

  defp segments(passages, total, range_label) do
    passages
    |> Enum.with_index()
    |> Enum.map(fn {passage, i} ->
      title =
        pair(fn ->
          "#{PlayLabels.verse_form_label(passage["form"])}#{verses_range(passage, range_label)} · " <>
            ngettext("%{count} verse", "%{count} verses", passage["verses"])
        end)

      %{
        sep: i > 0 and Enum.at(passages, i - 1)["act"] != passage["act"],
        colour: form_colour(passage["form"]),
        verses: passage["verses"],
        title: title,
        label: if(passage["verses"] / total > 0.06, do: form_label(passage["form"]))
      }
    end)
  end

  # A passage whose verses carry no number (a song) has no range to name.
  defp verses_range(%{"from" => nil}, _label), do: ""
  defp verses_range(passage, label), do: " · #{label} #{range(passage)}"

  defp range(%{"from" => from, "to" => to}) when from == to, do: "#{from}"
  defp range(%{"from" => from, "to" => to}), do: "#{from}–#{to}"

  defp form_label(form), do: pair(fn -> PlayLabels.verse_form_label(form) end)

  defp percent(part, total), do: "#{round(part / max(total, 1) * 100)}%"

  attr :characters, :list, required: true
  attr :unit, :string, required: true, doc: ~s("lines" or "words")
  attr :total, :integer, required: true

  def character_table(assigns) do
    characters =
      assigns.characters
      |> Enum.sort_by(&(-&1[assigns.unit]))
      |> Enum.map(&Map.put(&1, "main_forms", main_forms(&1["forms"])))

    max = characters |> Enum.map(& &1[assigns.unit]) |> Enum.max(fn -> 1 end) |> max(1)
    forms? = Enum.any?(characters, &(&1["main_forms"] != {"", ""}))
    assigns = assign(assigns, characters: characters, max: max, forms?: forms?)

    ~H"""
    <section :if={@characters != []} id="characters">
      <h2>{t("Characters")}</h2>
      <p :if={@unit == "lines"} class="lede">
        {t(
          "The %{n} speaking characters, those with the most lines first. A shared verse counts for each speaker.",
          n: length(@characters)
        )}
      </p>
      <p :if={@unit == "words"} class="lede">
        {t(
          "The %{n} speaking characters, those with the most words first. A shared verse counts for each speaker.",
          n: length(@characters)
        )}
      </p>
      <table>
        <thead>
          <tr>
            <th>{t("Character")}</th>
            <th class="num">{t("Speeches")}</th>
            <th class="num">{t("Lines")}</th>
            <th class="num">{t("Words")}</th>
            <th>{t("Share of the play")}</th>
            <th>{t("First speaks")}</th>
            <th :if={@forms?}>{t("Main forms")}</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={character <- @characters}>
            <th scope="row"><.inline text={character["name"]} /></th>
            <td class="num">{number(character["speeches"])}</td>
            <td class="num">{number(character["lines"])}</td>
            <td class="num">{number(character["words"])}</td>
            <td class="share" {attrs(share_title(character[@unit], @total, @unit), "title")}>
              <span class="track"><span style={"width: #{round(character[@unit] / @max * 100)}%"}></span></span>{percent(
                character[@unit],
                @total
              )}
            </td>
            <td>{first_speaks(character["first"])}</td>
            <td :if={@forms?}>{html(character["main_forms"])}</td>
          </tr>
        </tbody>
      </table>
    </section>
    """
  end

  # "I.2, 144": the act, its scene when it has scenes, and the line when it has a number.
  defp first_speaks(%{"act" => act} = first) when is_integer(act) do
    place = Enum.join([Edition.roman(act) | List.wrap(first["scene"])], ".")
    Enum.join([place | List.wrap(first["line"])], ", ")
  end

  defp first_speaks(_first), do: "—"

  defp main_forms(forms) do
    forms
    |> Map.delete("unmarked")
    |> Enum.sort_by(&(-elem(&1, 1)))
    |> Enum.take(2)
    |> Enum.map(&form_label(elem(&1, 0)))
    |> join(" · ")
  end

  defp share_title(n, total, "lines"), do: tp("%{n} of %{total} lines", n: n, total: total)
  defp share_title(n, total, "words"), do: tp("%{n} of %{total} words", n: n, total: total)

  attr :stats, :map, required: true
  attr :range_label, :string, default: "vv.", doc: "the word a range of numbers is cited with"

  def presence(assigns) do
    presence = assigns.stats["presence"] || %{}

    rows =
      (assigns.stats["characters"] || [])
      |> Enum.map(fn c -> {c["name"], Map.new(c["columns"], fn [i, n] -> {i, n} end)} end)

    assigns =
      assign(assigns, basis: presence["basis"], columns: presence["columns"] || [], rows: rows)

    ~H"""
    <section :if={@columns != [] and @rows != []} id="presence">
      <h2>{t("Who shares the stage")}</h2>
      <p class="lede">{basis_note(@basis, length(@columns))}</p>
      <div class="scroll">
        <table class="matrix">
          <thead>
            <tr>
              <th><span class="sr-only">{t("Character")}</span></th>
              <th
                :for={{column, i} <- Enum.with_index(@columns)}
                scope="col"
                {attrs(column_title(column, @range_label), "title")}
                class={act_start(@columns, i)}
              >
                <i :if={column["form"]} class={["sw", form_colour(column["form"])]}></i>
                <span class="sr-only">{html(column_title(column, @range_label))}</span>
              </th>
            </tr>
          </thead>
          <tbody>
            <tr :for={{name, cells} <- @rows}>
              <th scope="row"><.inline text={name} /></th>
              <td
                :for={{column, i} <- Enum.with_index(@columns)}
                class={["c", cells[i] && "on", act_start(@columns, i)]}
                {if cells[i], do: attrs(cell_title(name, column, @range_label, cells[i]), "title"), else: []}
              >
                <span :if={cells[i]} class="sr-only">
                  {tn("%{count} line", "%{count} lines", cells[i])}
                </span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
    """
  end

  defp basis_note("scene", _n), do: t("A filled cell means the character speaks in that scene.")

  defp basis_note("passage", n),
    do:
      t(
        "This play encodes no scenes, so the columns are its %{n} metrical passages. A filled cell means the character speaks in that passage.",
        n: n
      )

  defp basis_note(_basis, _n),
    do: t("A filled cell means the character speaks in that division.")

  # Each column's name, `{spanish, english}`: a verse form's in each language.
  defp column_title(%{"form" => form} = column, range_label),
    do: pair(fn -> "#{PlayLabels.verse_form_label(form)}#{verses_range(column, range_label)}" end)

  # The statistics keep a heading as stored, its italics marked: a title attribute takes
  # plain text.
  defp column_title(%{"act" => act, "label" => label}, _range_label) when is_integer(act),
    do: same("#{Edition.roman(act)}: #{InlineMarkup.plain(label)}")

  defp column_title(%{"label" => label}, _range_label), do: same(InlineMarkup.plain(label))

  defp cell_title(name, column, range_label, n) do
    {es, en} = column_title(column, range_label)
    {lines_es, lines_en} = pair(fn -> ngettext("%{count} line", "%{count} lines", n) end)
    name = InlineMarkup.plain(name)
    {"#{name} · #{es} · #{lines_es}", "#{name} · #{en} · #{lines_en}"}
  end

  defp act_start(columns, i),
    do:
      if(i > 0 and Enum.at(columns, i - 1)["act"] != Enum.at(columns, i)["act"], do: "act-start")

  # The site's key for each of Play.relationship_types/0: its catalogue's filter values.
  @kinds %{
    "traduccion" => "translation",
    "adaptacion" => "adaptation",
    "version" => "version"
  }

  @doc "A language's name in the interface's two languages, `{spanish, english}`."
  def language("es"), do: tp("Spanish")
  def language("en"), do: tp("English")
  def language("it"), do: tp("Italian")
  def language("ca"), do: tp("Catalan")
  def language("fr"), do: tp("French")
  def language("pt"), do: tp("Portuguese")
  def language("de"), do: tp("German")
  def language(code), do: {code, code}

  @doc "A kind's name in the catalogue's and the search's facets, `{spanish, english}`."
  def kind_label("original"), do: tp("Originals")
  def kind_label("translation"), do: tp("Translations")
  def kind_label("adaptation"), do: tp("Adaptations")
  def kind_label("version"), do: tp("Versions")

  @doc "The site's key for a play's kind: original, translation, adaptation or version."
  def kind(%{relationship_type: nil}), do: "original"
  def kind(%{relationship_type: type}), do: Map.fetch!(@kinds, type)

  @doc "A play's kind as a word in both languages, `{spanish, english}`."
  def kind_word(play) do
    case kind(play) do
      "original" -> tp("original")
      "translation" -> tp("translation")
      "adaptation" -> tp("adaptation")
      "version" -> tp("version")
    end
  end

  # What a play is of its original, before the original's title.
  defp relation(play) do
    case kind(play) do
      "translation" -> t("Translation of")
      "adaptation" -> t("Adaptation of")
      "version" -> t("Version of")
    end
  end

  # A play's language in its family list, and its kind when it has one: "French,
  # adaptation". FileMaker linked a few plays with no kind.
  defp family_role(play) do
    case kind(play) do
      "original" -> language(play.language)
      _kind -> join([language(play.language), kind_word(play)], ", ")
    end
  end

  def collection(%{code: "AL" <> _}), do: "ARTELOPE"
  def collection(_play), do: "EMOTHE"

  attr :play, :map, required: true
  attr :lead, :boolean, default: false
  attr :compare, :string, default: nil, doc: "the code of the play the Compare link opens"

  def catalogue_entry(assigns) do
    ~H"""
    <div
      class="entry"
      data-play
      data-lang={@play.language}
      data-form={Play.form(@play)}
      data-kind={kind(@play)}
      data-coll={collection(@play)}
      data-text={
        Search.normalise(
          Enum.join([@play.title, @play.original_title, @play.author_name, @play.code], " ")
        )
      }
    >
      <span class="tag">{@play.language}</span>
      <a class={["entry-title", @lead && "lead"]} href={"plays/#{@play.code}/index.html"}>
        {@play.title}
      </a>
      <span class="code">{@play.code}</span>
      <a
        :if={@compare}
        class="compare"
        href={"plays/#{@compare}/compare.html"}
        {ta(["aria-label", "title"], "Compare")}
      >
        <svg viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
          <path
            fill-rule="evenodd"
            d="M13.2 2.24a.75.75 0 0 0 .04 1.06l2.1 1.95H6.75a.75.75 0 0 0 0 1.5h8.59l-2.1 1.95a.75.75 0 1 0 1.02 1.1l3.5-3.25a.75.75 0 0 0 0-1.1l-3.5-3.25a.75.75 0 0 0-1.06.04Zm-6.4 8a.75.75 0 0 0-1.06-.04l-3.5 3.25a.75.75 0 0 0 0 1.1l3.5 3.25a.75.75 0 1 0 1.02-1.1l-2.1-1.95h8.59a.75.75 0 0 0 0-1.5H4.66l2.1-1.95a.75.75 0 0 0 .04-1.06Z"
            clip-rule="evenodd"
          />
        </svg>
      </a>
      <span :if={kind(@play) != "original"} class="tag">{html(kind_word(@play))}</span>
      <span class="meta">{entry_meta(@play)}</span>
      <span :if={@lead} class="author">{@play.author_name}</span>
    </div>
    """
  end

  defp entry_meta(play) do
    form =
      case Play.form(play) do
        "verse" when is_integer(play.verse_count) and play.verse_count > 0 ->
          same("#{number(play.verse_count)} vv.")

        form ->
          pair(fn -> PlayLabels.form_label(form) end)
      end

    case Play.composition_years(play) do
      nil -> html(form)
      years -> html(join([same(years), form], " · "))
    end
  end
end
