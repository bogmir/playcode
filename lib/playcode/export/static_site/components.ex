defmodule Playcode.Export.StaticSite.Components do
  @moduledoc """
  The pieces the static site's pages are built from. Plain semantic HTML: the classes
  belong to `priv/static_site/style.css`, and the `data-*` attributes are the hooks
  `site.js` and `search.js` enhance.
  """
  use Phoenix.Component

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

  attr :title, :string, required: true
  attr :site, :map, required: true
  attr :current, :atom, default: nil
  attr :play, :map, default: nil, doc: "the play shown, whose licence the footer states"
  attr :rail_label, :string, default: "Contents & tools"
  slot :rail
  slot :inner_block, required: true

  def shell(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>{@title}</title>
        <%!-- Not stamped like the links below: it must match style.css's url(), or the font is fetched twice. --%>
        <link
          rel="preload"
          href={@root <> "assets/fonts/source-serif-4-400-latin.woff2"}
          as="font"
          type="font/woff2"
          crossorigin
        />
        <link rel="stylesheet" href={@root <> "assets/style.css?v=" <> @site.assets} />
        <script src={@root <> "assets/site.js?v=" <> @site.assets} defer>
        </script>
      </head>
      <body data-ln="5" data-fo="off">
        <header class="bar">
          <a class="wordmark" href={@root <> "index.html"}>EMOTHE</a>
          <nav aria-label="Site">
            <a href={@root <> "index.html"} aria-current={@current == :catalogue && "page"}>
              catalogue
            </a>
            <a href={@root <> "search.html"} aria-current={@current == :search && "page"}>search</a>
            <a href={@root <> "about.html"} aria-current={@current == :about && "page"}>about</a>
          </nav>
        </header>
        <div class={["frame", @rail != [] && "with-rail"]}>
          <details :if={@rail != []} class="rail" open>
            <summary>{@rail_label}</summary>
            {render_slot(@rail)}
          </details>
          <main id="main">{render_slot(@inner_block)}</main>
        </div>
        <footer class="foot">
          <p :if={@play && licence?(@play)}>
            <.licence play={@play} />
          </p>
          <p>EMOTHE · version {@site.version} · built {@site.build_date}</p>
          <p>
            A static edition following the <a href="https://endings.uvic.ca/principles.html">Endings principles</a>; every play's TEI-XML source is published beside it.
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

  def licence?(play), do: play.licence_text not in [nil, ""] or play.licence_url not in [nil, ""]

  defp web_url?(url), do: is_binary(url) and String.starts_with?(url, ["http://", "https://"])

  attr :edition, :map, required: true
  attr :current, :string, required: true
  attr :tools, :boolean, default: false

  def play_rail(assigns) do
    assigns = assign(assigns, :cast, Enum.filter(cast(assigns.edition.characters), & &1.xml_id))

    ~H"""
    <nav aria-label="Contents">
      <h2>Contents</h2>
      <.play_contents edition={@edition} current={@current} />
    </nav>
    <div :if={@tools} class="tools" data-tools hidden>
      <h2>Line numbers</h2>
      <div class="seg" role="group" aria-label="Line numbers">
        <button type="button" data-ln-set="all">All</button>
        <button type="button" data-ln-set="5">5</button>
        <button type="button" data-ln-set="off">Off</button>
      </div>
      <h2>Show</h2>
      <label><input type="checkbox" data-toggle="sd" checked /> Stage directions</label>
      <label><input type="checkbox" data-toggle="vf" checked /> Verse forms</label>
      <label :if={@edition.variants}>
        <input type="checkbox" data-toggle="va" checked /> Variants
      </label>
      <label :if={@edition.folio}>
        <input type="checkbox" data-toggle="fo" /> Folio interpolations
      </label>
      <%= if @cast != [] do %>
        <h2>Highlight</h2>
        <select data-highlight aria-label="Highlight a character">
          <option value="">No one</option>
          <option :for={character <- @cast} value={character.xml_id}>
            {InlineMarkup.plain(character.name)}
          </option>
        </select>
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
      <li><a href="index.html" aria-current={@current == "index" && "page"}>Title page</a></li>
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
      <li><a href="text.html" aria-current={@current == "text" && "page"}>Full text</a></li>
      <li>
        <a href="statistics.html" aria-current={@current == "statistics" && "page"}>Statistics</a>
      </li>
      <li :if={@edition.notes != []}>
        <a href="notes.html" aria-current={@current == "notes" && "page"}>Notes</a>
      </li>
      <li :if={@edition.play.witnesses != []}>
        <a href="index.html#witnesses">Witnesses</a>
      </li>
      <li :if={@edition.performances != []}>
        <a href="index.html#performances">Performances</a>
      </li>
      <li :if={@edition.bibliography != []}>
        <a href="index.html#bibliography">Bibliography</a>
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

  defp item_title(%Paratext{} = paratext), do: PlayLabels.paratext_title(paratext)
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
      <dt>Historical time</dt>
      <dd>
        {PlayLabels.historical_time_label(@play.historical_time)}
        <span :if={@play.historical_time_note} class="note">{@play.historical_time_note}</span>
      </dd>
    <% end %>
    <%= if @play.composition_date_from || @play.composition_date_note do %>
      <dt>Composition</dt>
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
      <h2>Work family</h2>
      <p :if={@original}>
        {String.capitalize(kind_name(kind(@play)))} of
        <a href={"../#{@original.code}/index.html"}><cite>{@original.title}</cite></a>
      </p>
      <ul :if={@derived != []}>
        <li :for={play <- @derived}>
          <a href={"../#{play.code}/index.html"}><cite>{play.title}</cite></a>
          <span class="role">{family_role(play)}</span>
        </li>
      </ul>
    </section>
    """
  end

  attr :play, :map, required: true

  # The bibliography's class gives the hanging indent; no CSS of its own.
  def witnesses(assigns) do
    ~H"""
    <section :if={@play.witnesses != []} id="witnesses" class="bibliography">
      <h2>Witnesses</h2>
      <ul>
        <li :for={witness <- @play.witnesses}>{Witnesses.html(witness)}</li>
      </ul>
    </section>
    """
  end

  attr :edition, :map, required: true

  # Layout B: a line each, the sources they cite once below. The site's interface is in
  # English and its place names in Spanish, as the Places section's.
  def performances(assigns) do
    assigns = assign(assigns, :listing, performance_listing(assigns.edition))

    ~H"""
    <section :if={@listing.lines != []} id="performances" class="performances">
      <h2>Performances</h2>
      <ul>
        <li :for={line <- @listing.lines} class="performance">
          <b :if={line.date}><.inline text={line.date} /></b>
          <.inline :if={line.parts != []} text={Enum.join(line.parts, " · ")} />
          <span :if={line.reference} class="note">
            {line.reference}
          </span>
          <p :if={line.cast != []} class="note">
            Cast: <.inline text={Enum.join(line.cast, "; ")} />
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
  defp performance_listing(%{performances: performances, characters: characters}) do
    gazetteer = if Enum.any?(performances, & &1.place), do: Playcode.Places.gazetteer(), else: %{}
    Performances.listing(performances, characters, gazetteer, "en", "es")
  end

  attr :groups, :list, required: true

  def bibliography(assigns) do
    ~H"""
    <section :if={@groups != []} id="bibliography" class="bibliography">
      <h2>Bibliography</h2>
      <%= for {kind, subgroups} <- @groups do %>
        <h3>{PlayLabels.bibliography_kind_label(kind)}</h3>
        <%= for {language, links} <- subgroups do %>
          <h4 :if={kind == "translation"}>{PlayLabels.bibliography_language_label(language)}</h4>
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
      <h2>Places</h2>
      <ul>
        <li :for={{name, mentioned?, note} <- @links}>
          {name}<span :if={mentioned?} class="role"> (mentioned)</span>
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
        <h2 class={@head}><.inline text={@item.heading || PlayLabels.kind_label(@item.kind)} /></h2>
      <% end %>
      <p :for={paragraph <- paragraphs(@item.content)}><.inline text={paragraph} /></p>
      <p :if={@item.trailer} class="tr"><.inline text={@item.trailer} /></p>
    </section>
    """
  end

  def outline_item(%{item: %{parent_id: nil}} = assigns) do
    ~H"""
    <section id={@edition.anchors[@item.id]}>
      <h2 class={@head}>
        <.inline text={@item.title || "Dramatis personae"} notes={@item.notes} />
      </h2>
      <.cast_entries entries={@item.entries} />
    </section>
    """
  end

  def outline_item(assigns) do
    ~H"""
    <section id={@edition.anchors[@item.id]}>
      <h3 :if={@item.title} class="scene-head">
        <.inline text={@item.title} notes={@item.notes} />
      </h3>
      <.cast_entries entries={@item.entries} />
    </section>
    """
  end

  attr :entries, :list, required: true

  # A cast list's own entries, a group's under its heading.
  defp cast_entries(assigns) do
    ~H"""
    <%= for [first | _] = group <- CastListEntry.printed_groups(@entries) do %>
      <p :if={first.group_heading} class="cast-group"><.inline text={first.group_heading} /></p>
      <dl class="cast">
        <%= for entry <- group do %>
          <dt><.inline text={entry.name} /></dt>
          <dd><.inline text={entry.description} /></dd>
        <% end %>
      </dl>
    <% end %>
    """
  end

  @doc "What the title page says about the play's form."
  def form_summary(play, stats) do
    verses = stats["verses"] || 0

    case {Play.form(play), verses} do
      {"prose", _} -> "Prose"
      {"verse", n} when n > 0 -> "Verse · #{number(n)} verses"
      {"verse", _} -> "Verse"
      {"mixed", n} when n > 0 -> "Verse and prose · #{number(n)} verses"
      {"mixed", _} -> "Verse and prose"
    end
  end

  @doc "An integer with its thousands separated by commas."
  def number(nil), do: "0"

  def number(n) when is_integer(n),
    do: n |> Integer.to_string() |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, ",")

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

    [
      play.author_name,
      play.title,
      editors != [] && "ed. " <> Enum.join(editors, ", "),
      "EMOTHE, version #{site.version} (#{String.slice(site.build_date, 0, 4)})"
    ]
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.join(". ")
    |> Kernel.<>(".")
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
    <nav :if={@prev || @next} class="pager" aria-label="Acts">
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
  attr :division, :map, required: true

  def division_text(assigns) do
    {opening, rest} = Division.split_opening_lists(assigns.division.children)
    assigns = assign(assigns, opening: opening, rest: rest)

    ~H"""
    <section class="division" id={@edition.anchors[@division.id]}>
      <h2 :if={@division.title} class="act-head">
        <.inline text={@division.title} notes={@division.notes} />
      </h2>
      <.outline_item :for={list <- @opening} edition={@edition} item={list} />
      <.el :for={el <- @division.loaded_elements} el={el} edition={@edition} />
      <%= for child <- @rest do %>
        <%= if child.type == "elenco" do %>
          <.outline_item edition={@edition} item={child} />
        <% else %>
          <section id={@edition.anchors[child.id]}>
            <h3 :if={child.title} class="scene-head">
              <.inline text={child.title} notes={child.notes} />
            </h3>
            <.el :for={el <- child.loaded_elements} el={el} edition={@edition} />
          </section>
        <% end %>
      <% end %>
    </section>
    """
  end

  attr :edition, :map, required: true
  attr :page, :map, required: true

  @doc """
  What one division page shows: the division whole; or, for a division split by scene,
  its own text and a list of its scene pages; or one scene of it.
  """
  def page_text(%{page: %{scene: nil, split: false}} = assigns) do
    ~H"""
    <.division_text edition={@edition} division={@page.division} />
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
      <.el :for={el <- @page.division.loaded_elements} el={el} edition={@edition} />
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
        <.el :for={el <- @page.scene.loaded_elements} el={el} edition={@edition} />
      </section>
    </section>
    """
  end

  attr :el, :map, required: true
  attr :edition, :map, required: true

  defp el(%{el: %{type: "speech"}} = assigns) do
    assigns = assign(assigns, :who, who(assigns.el))

    ~H"""
    <div class={["sp", Element.folio_only?(@el) && "fo"]} data-who={@who}>
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
        form: edition.passage_starts[assigns.el.id]
      )

    ~H"""
    <div
      phx-no-format
      class={[
        "l",
        @el.rend == "indent" && "indent",
        Element.folio_only?(@el) && "fo",
        orphan_part(@el, @ghost)
      ]}
      id={@anchor}
    ><a :if={@el.line_number} class={["n", rem(@el.line_number, 5) == 0 && "m5"]} href={"#" <> @anchor}>{@el.line_number}</a><span class="t"><span :if={@ghost} class="ghost" aria-hidden="true"><.inline text={@ghost} /> </span><.inline text={@el.content} notes={@el.notes} /></span><span :if={@form || @el.is_aside} class="margin"><span :if={@form} class="vf">{PlayLabels.verse_form_label(@form)}</span><span :if={@el.is_aside} class="aparte">aparte</span></span></div>
    """
  end

  defp el(%{el: %{type: "stage_direction"}} = assigns) do
    ~H"""
    <p phx-no-format class={["sd", Element.folio_only?(@el) && "fo"]} id={@edition.anchors[@el.id]}><.inline text={@el.content} notes={@el.notes} /></p>
    """
  end

  defp el(%{el: %{type: "prose"}} = assigns) do
    ~H"""
    <p phx-no-format class={["pr", Element.folio_only?(@el) && "fo"]} id={@edition.anchors[@el.id]}><.inline text={@el.content} notes={@el.notes} /></p>
    """
  end

  # An opening formula (the Arte nuevo's dedication) or a closing one, centred alike.
  defp el(%{el: %{type: type}} = assigns) when type in ~w(opener trailer) do
    ~H"""
    <p class="tr" id={@edition.anchors[@el.id]}><.inline text={@el.content} notes={@el.notes} /></p>
    """
  end

  defp el(assigns), do: ~H""

  # A middle or last part with no earlier part to line up after (prose or a whole verse
  # before it) steps in by a fixed indent instead, as emothe.uv.es printed it.
  defp orphan_part(%{part: part}, nil) when part in ["M", "F"],
    do: "part-" <> String.downcase(part)

  defp orphan_part(_el, _ghost), do: nil

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

  # Where a printed line of the source starts, in prose: its number, which the "Line
  # numbers" control hides (style.css), every fifth kept by "5". Not a link: a play that
  # counts its paragraphs restarts at 1, so an id built from the number would repeat.
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
    label = escape("#{PlayLabels.note_type_label(note.type)} #{number}")

    [
      ~s(<button type="button" id="nref-),
      number,
      ~s(" class="nref" popovertarget="note-),
      number,
      ~s(" aria-label="),
      label,
      ~s(">),
      number,
      "</button>"
    ]
  end

  defp variant_ref(note) do
    number = Integer.to_string(note.number)

    [
      ~s(<button type="button" class="vref" popovertarget="var-),
      number,
      ~s(" aria-label="),
      escape("#{PlayLabels.note_type_label(note.type)} #{number}"),
      ~s(">*</button>)
    ]
  end

  defp breaks(text), do: text |> escape() |> String.replace("\n", "<br>")

  defp fifth?(n), do: match?({i, ""} when rem(i, 5) == 0, Integer.parse(n))

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  attr :notes, :list, required: true

  @doc """
  A page's notes. Each is a popover its marker opens (`part/1`); in print, and in a
  browser without popover, they are the page's endnotes, its variants after them.
  """
  def endnotes(assigns) do
    {variants, notes} = Enum.split_with(assigns.notes, &Note.variant?/1)
    assigns = assign(assigns, notes: notes, variants: variants)

    ~H"""
    <section :if={@notes != []} class="notes" role="doc-endnotes" aria-label="Notes">
      <ol>
        <li :for={note <- @notes} id={"note-#{note.number}"} popover value={note.number}>
          <button
            type="button"
            popovertarget={"note-#{note.number}"}
            popovertargetaction="hide"
            aria-label="Close"
          >
            ×
          </button>
          <b>{PlayLabels.note_type_label(note.type)}</b>
          <i :if={note.term}><.inline text={note.term} /></i>
          <p :for={paragraph <- Note.paragraphs(note)}><.inline text={paragraph} /></p>
        </li>
      </ol>
    </section>
    <section :if={@variants != []} class="notes" aria-label="Textual variants">
      <ul>
        <li :for={variant <- @variants} id={"var-#{variant.number}"} popover>
          <button
            type="button"
            popovertarget={"var-#{variant.number}"}
            popovertargetaction="hide"
            aria-label="Close"
          >
            ×
          </button>
          <b>{PlayLabels.note_type_label(variant.type)}</b>
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
          {s["num_acts"], "acts"},
          {s["verses"], "verses"},
          {length(s["metrical_passages"] || []), "metrical passages"},
          {s["speeches"], "speeches"},
          {length(s["characters"] || []), "speaking characters"},
          {s["total_stage_directions"], "stage directions"},
          {s["aside_verses"], "verses in asides"}
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

  def synopsis(assigns) do
    total = assigns.passages |> Enum.map(& &1["verses"]) |> Enum.sum() |> max(1)

    # By label, so romance and romance_tirada, both "Romance", are one form.
    forms =
      assigns.passages
      |> Enum.group_by(&PlayLabels.verse_form_label(&1["form"]))
      |> Enum.map(fn {label, [first | _] = passages} ->
        {label, form_colour(first["form"]), passages |> Enum.map(& &1["verses"]) |> Enum.sum()}
      end)
      |> Enum.sort_by(&(-elem(&1, 2)))

    assigns =
      assign(assigns,
        segments: segments(assigns.passages, total),
        forms: forms,
        total: total
      )

    ~H"""
    <section id="synopsis">
      <h2>Metrical synopsis</h2>
      <p class="lede">
        The verse forms in order, each passage drawn to scale. Dashed lines mark the acts.
      </p>
      <div
        class="band"
        role="img"
        aria-label="Metrical synopsis drawn to scale; the table below lists every passage."
      >
        <%= for segment <- @segments do %>
          <span :if={segment.sep} class="sep"></span>
          <span
            class={["pass", segment.colour]}
            style={"flex-grow: #{segment.verses}"}
            title={segment.title}
          >
            <span :if={segment.label}>{segment.label}</span>
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
            <th>Act</th>
            <th>Form</th>
            <th>vv.</th>
            <th class="num">Verses</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={passage <- @passages}>
            <td>{passage["act"] && Edition.roman(passage["act"])}</td>
            <td>
              <i class={["sw", form_colour(passage["form"])]}></i>{PlayLabels.verse_form_label(
                passage["form"]
              )}
            </td>
            <td>{range(passage)}</td>
            <td class="num">{number(passage["verses"])}</td>
          </tr>
        </tbody>
      </table>
      <p class="note">
        Rhyme is not encoded, so two consecutive romances with different assonance show as one passage.
      </p>
    </section>
    """
  end

  defp segments(passages, total) do
    passages
    |> Enum.with_index()
    |> Enum.map(fn {passage, i} ->
      label = PlayLabels.verse_form_label(passage["form"])

      %{
        sep: i > 0 and Enum.at(passages, i - 1)["act"] != passage["act"],
        colour: form_colour(passage["form"]),
        verses: passage["verses"],
        title: "#{label}#{verses_range(passage)} · #{passage["verses"]} verses",
        label: if(passage["verses"] / total > 0.06, do: label)
      }
    end)
  end

  # A passage whose verses carry no number (a song) has no range to name.
  defp verses_range(%{"from" => nil}), do: ""
  defp verses_range(passage), do: " · vv. #{range(passage)}"

  defp range(%{"from" => from, "to" => to}) when from == to, do: "#{from}"
  defp range(%{"from" => from, "to" => to}), do: "#{from}–#{to}"

  defp percent(part, total), do: "#{round(part / max(total, 1) * 100)}%"

  attr :characters, :list, required: true
  attr :unit, :string, required: true, doc: ~s("lines" or "words")
  attr :total, :integer, required: true

  def character_table(assigns) do
    top = assigns.characters |> Enum.sort_by(&(-&1[assigns.unit])) |> Enum.take(12)
    max = top |> Enum.map(& &1[assigns.unit]) |> Enum.max(fn -> 1 end) |> max(1)
    assigns = assign(assigns, top: top, max: max)

    ~H"""
    <section :if={@top != []} id="characters">
      <h2>Characters</h2>
      <p class="lede">
        The {length(@top)} speaking characters with the most {@unit}{if length(@characters) >
                                                                          length(@top),
                                                                        do:
                                                                          " (of #{length(@characters)})"}. A shared verse counts for each speaker.
      </p>
      <table>
        <thead>
          <tr>
            <th>Character</th>
            <th class="num">Speeches</th>
            <th class="num">Lines</th>
            <th class="num">Words</th>
            <th>Share of the play</th>
            <th>First words</th>
            <th>Main forms</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={character <- @top}>
            <th scope="row">{character["name"]}</th>
            <td class="num">{number(character["speeches"])}</td>
            <td class="num">{number(character["lines"])}</td>
            <td class="num">{number(character["words"])}</td>
            <td class="share" title={"#{character[@unit]} of #{@total} #{@unit}"}>
              <span class="track"><span style={"width: #{round(character[@unit] / @max * 100)}%"}></span></span>{percent(
                character[@unit],
                @total
              )}
            </td>
            <td>{first_words(character["first"])}</td>
            <td>{main_forms(character["forms"])}</td>
          </tr>
        </tbody>
      </table>
    </section>
    """
  end

  defp first_words(%{"act" => act, "line" => line}) when is_integer(act) and is_integer(line),
    do: "#{Edition.roman(act)}, #{line}"

  defp first_words(%{"act" => act}) when is_integer(act), do: Edition.roman(act)
  defp first_words(_first), do: "—"

  defp main_forms(forms) do
    forms
    |> Map.delete("unmarked")
    |> Enum.sort_by(&(-elem(&1, 1)))
    |> Enum.take(2)
    |> Enum.map_join(" · ", &PlayLabels.verse_form_label(elem(&1, 0)))
  end

  attr :stats, :map, required: true

  def presence(assigns) do
    presence = assigns.stats["presence"] || %{}

    rows =
      (assigns.stats["characters"] || [])
      |> Enum.take(12)
      |> Enum.map(fn c -> {c["name"], Map.new(c["columns"], fn [i, n] -> {i, n} end)} end)

    assigns =
      assign(assigns, basis: presence["basis"], columns: presence["columns"] || [], rows: rows)

    ~H"""
    <section :if={@columns != [] and @rows != []} id="presence">
      <h2>Who shares the stage</h2>
      <p class="lede">{basis_note(@basis, length(@columns))}</p>
      <div class="scroll">
        <table class="matrix">
          <thead>
            <tr>
              <th><span class="sr-only">Character</span></th>
              <th
                :for={{column, i} <- Enum.with_index(@columns)}
                scope="col"
                title={column_title(column)}
                class={act_start(@columns, i)}
              >
                <i :if={column["form"]} class={["sw", form_colour(column["form"])]}></i>
                <span class="sr-only">{column_title(column)}</span>
              </th>
            </tr>
          </thead>
          <tbody>
            <tr :for={{name, cells} <- @rows}>
              <th scope="row">{name}</th>
              <td
                :for={{column, i} <- Enum.with_index(@columns)}
                class={["c", cells[i] && "on", act_start(@columns, i)]}
                title={cells[i] && "#{name} · #{column_title(column)} · #{cells[i]} lines"}
              >
                <span :if={cells[i]} class="sr-only">
                  {cells[i]} {if cells[i] == 1, do: "line", else: "lines"}
                </span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
    """
  end

  defp basis_note("scene", _n), do: "A filled cell means the character speaks in that scene."

  defp basis_note("passage", n),
    do:
      "This play encodes no scenes, so the columns are its #{n} metrical passages. A filled cell means the character speaks in that passage."

  defp basis_note(_basis, _n), do: "A filled cell means the character speaks in that division."

  defp column_title(%{"form" => form} = column),
    do: "#{PlayLabels.verse_form_label(form)}#{verses_range(column)}"

  # The statistics keep a heading as stored, its italics marked: a title attribute takes
  # plain text.
  defp column_title(%{"act" => act, "label" => label}) when is_integer(act),
    do: "#{Edition.roman(act)}: #{InlineMarkup.plain(label)}"

  defp column_title(%{"label" => label}), do: InlineMarkup.plain(label)

  defp act_start(columns, i),
    do:
      if(i > 0 and Enum.at(columns, i - 1)["act"] != Enum.at(columns, i)["act"], do: "act-start")

  # The site's English word for each of Play.relationship_types/0.
  @kinds %{
    "traduccion" => "translation",
    "adaptacion" => "adaptation",
    "refundicion" => "refundicion",
    "version" => "version"
  }

  @doc "The site's word for a play's kind: original, translation, adaptation, refundicion or version."
  def kind(%{relationship_type: nil}), do: "original"
  def kind(%{relationship_type: type}), do: Map.fetch!(@kinds, type)

  # A play's language in its family list, and its kind when it has one: "Français,
  # adaptation". FileMaker linked a few plays with no kind.
  defp family_role(play) do
    case kind(play) do
      "original" -> Play.language_name(play.language)
      kind -> "#{Play.language_name(play.language)}, #{kind_name(kind)}"
    end
  end

  @doc ~s(A kind in a sentence: "adaptation", "refundición".)
  def kind_name("refundicion"), do: "refundición"
  def kind_name(kind), do: kind

  def collection(%{code: "AL" <> _}), do: "ARTELOPE"
  def collection(_play), do: "EMOTHE"

  attr :play, :map, required: true
  attr :lead, :boolean, default: false

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
      <span :if={kind(@play) != "original"} class="tag">{kind_name(kind(@play))}</span>
      <span class="meta">{entry_meta(@play)}</span>
      <span :if={@lead} class="author">{@play.author_name}</span>
    </div>
    """
  end

  defp entry_meta(play) do
    form =
      case Play.form(play) do
        "prose" ->
          "Prose"

        "mixed" ->
          "Verse and prose"

        "verse" when is_integer(play.verse_count) and play.verse_count > 0 ->
          "#{number(play.verse_count)} vv."

        "verse" ->
          "Verse"
      end

    [Play.composition_years(play), form] |> Enum.reject(&is_nil/1) |> Enum.join(" · ")
  end
end
