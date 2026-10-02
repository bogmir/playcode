defmodule Playcode.Export.StaticSite.Components do
  @moduledoc """
  The pieces the static site's pages are built from. Plain semantic HTML: the classes
  belong to `priv/static_site/style.css`, and the `data-*` attributes are the hooks
  `site.js` and `search.js` enhance.
  """
  use Phoenix.Component

  alias Playcode.Catalogue.Play
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
        <link
          rel="preload"
          href={@root <> "assets/fonts/source-serif-4-400-latin.woff2"}
          as="font"
          type="font/woff2"
          crossorigin
        />
        <link rel="stylesheet" href={@root <> "assets/style.css"} />
        <script src={@root <> "assets/site.js"} defer>
        </script>
      </head>
      <body data-ln="5">
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

  def play_rail(assigns) do
    ~H"""
    <nav aria-label="Contents">
      <h2>Contents</h2>
      <.play_contents edition={@edition} current={@current} />
    </nav>
    """
  end

  attr :edition, :map, required: true
  attr :current, :string, default: nil
  attr :all_scenes, :boolean, default: false

  def play_contents(assigns) do
    ~H"""
    <ul>
      <li><a href="index.html" aria-current={@current == "index" && "page"}>Title page</a></li>
      <li :for={page <- @edition.pages}>
        <a href={page.slug <> ".html"} aria-current={@current == page.slug && "page"}>{page.title}</a>
        <ul :if={(@all_scenes or @current == page.slug) and page.division.children != []}>
          <li :for={scene <- page.division.children}>
            <a href={"#{page.slug}.html##{@edition.anchors[scene.id]}"}>
              {scene.title || "Scene #{scene.position + 1}"}
            </a>
          </li>
        </ul>
      </li>
      <li><a href="text.html" aria-current={@current == "text" && "page"}>Full text</a></li>
      <li>
        <a href="statistics.html" aria-current={@current == "statistics" && "page"}>Statistics</a>
      </li>
    </ul>
    """
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
        {composition_years(@play)}
        <span :if={@play.composition_date_note} class="note">{@play.composition_date_note}</span>
      </dd>
    <% end %>
    """
  end

  attr :play, :map, required: true
  attr :published, :any, required: true

  def family(assigns) do
    published? = &(&1 && MapSet.member?(assigns.published, &1.code))

    assigns =
      assign(assigns,
        original: if(published?.(assigns.play.parent_play), do: assigns.play.parent_play),
        translations: Enum.filter(assigns.play.derived_plays, published?)
      )

    ~H"""
    <section :if={@original || @translations != []}>
      <h2>Work family</h2>
      <p :if={@original}>
        Translation of <a href={"../#{@original.code}/index.html"}><cite>{@original.title}</cite></a>
      </p>
      <ul :if={@translations != []}>
        <li :for={translation <- @translations}>
          <a href={"../#{translation.code}/index.html"}><cite>{translation.title}</cite></a>
          <span class="role">{Play.language_name(translation.language)}</span>
        </li>
      </ul>
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
      &{Playcode.Places.breadcrumb(&1.place, gazetteer, "es"), &1.role == "mentioned", &1.note}
    )
  end

  defp place_links(_play), do: []

  @doc "The cast as published: every character not marked hidden."
  def cast(characters), do: Enum.reject(characters, & &1.is_hidden)

  @doc "What the title page says about the play's form, from the computed verse count."
  def form_summary(%{"verses" => n}) when is_integer(n) and n > 0,
    do: "Verse · #{number(n)} verses"

  def form_summary(_stats), do: "Prose"

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
    |> Enum.join(". ")
  end

  def paragraphs(nil), do: []
  def paragraphs(text), do: String.split(text, ~r/\n\s*\n/, trim: true)

  def note_heading("dedicatoria"), do: "Dedication"
  def note_heading("introduccion_editor"), do: "Editor's introduction"
  def note_heading("argumento"), do: "Argument"
  def note_heading("prologo"), do: "Prologue"
  def note_heading(_other), do: "Note"

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

  def composition_years(%{composition_date_from: nil}), do: nil

  def composition_years(%{composition_date_from: from, composition_date_to: to})
      when to in [nil, from],
      do: "#{from}"

  def composition_years(%{composition_date_from: from, composition_date_to: to}),
    do: "#{from}–#{to}"
end
