defmodule Playcode.Export.StaticSite.Components do
  @moduledoc """
  The pieces the static site's pages are built from. Plain semantic HTML: the classes
  belong to `priv/static_site/style.css`, and the `data-*` attributes are the hooks
  `site.js` and `search.js` enhance.
  """
  use Phoenix.Component

  alias Playcode.Catalogue.Play
  alias Playcode.Export.StaticSite.Edition
  alias Playcode.PlayContent.{Element, InlineMarkup}
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
    ~H"""
    <section class="division" id={@edition.anchors[@division.id]}>
      <h2 :if={@division.title} class="act-head">{@division.title}</h2>
      <.el :for={el <- @division.loaded_elements} el={el} edition={@edition} />
      <section :for={scene <- @division.children} id={@edition.anchors[scene.id]}>
        <h3 :if={scene.title} class="scene-head">{scene.title}</h3>
        <.el :for={el <- scene.loaded_elements} el={el} edition={@edition} />
      </section>
    </section>
    """
  end

  attr :el, :map, required: true
  attr :edition, :map, required: true

  defp el(%{el: %{type: "speech"}} = assigns) do
    assigns = assign(assigns, :who, who(assigns.el))

    ~H"""
    <div class="sp" data-who={@who}>
      <p :if={@el.speaker_label} class="spk">{@el.speaker_label}</p>
      <.el :for={child <- @el.children} el={child} edition={@edition} />
    </div>
    """
  end

  defp el(%{el: %{type: "line_group"}} = assigns) do
    ~H"""
    <div class="lg">
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
    <div phx-no-format class={["l", @el.rend == "indent" && "indent"]} id={@anchor}><a :if={@el.line_number} class={["n", rem(@el.line_number, 5) == 0 && "m5"]} href={"#" <> @anchor}>{@el.line_number}</a><span class="t"><span :if={@ghost} class="ghost" aria-hidden="true">{@ghost} </span><.inline text={@el.content} /></span><span :if={@form || @el.is_aside} class="margin"><span :if={@form} class="vf">{PlayLabels.verse_form_label(@form)}</span><span :if={@el.is_aside} class="aparte">aparte</span></span></div>
    """
  end

  defp el(%{el: %{type: "stage_direction"}} = assigns) do
    ~H"""
    <p class="sd" id={@edition.anchors[@el.id]}><.inline text={@el.content} /></p>
    """
  end

  defp el(%{el: %{type: "prose"}} = assigns) do
    ~H"""
    <p class="pr" id={@edition.anchors[@el.id]}><.inline text={@el.content} /></p>
    """
  end

  defp el(assigns), do: ~H""

  defp who(speech) do
    case for(character <- Element.characters(speech), character.xml_id, do: character.xml_id) do
      [] -> nil
      ids -> Enum.join(ids, " ")
    end
  end

  attr :text, :string, default: nil

  def inline(assigns) do
    assigns = assign(assigns, :parts, InlineMarkup.parts(assigns.text))

    # Built as iodata, not a template: the formatter indents EEx blocks, and the
    # whitespace it adds between a word and its <em> would be visible.
    ~H"""
    {Phoenix.HTML.raw(Enum.map(@parts, &part/1))}
    """
  end

  defp part(%{italic: true, text: text}),
    do: ["<em>", escape(text), "</em>"]

  defp part(%{text: text}), do: escape(text)

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

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

  attr :passages, :list, required: true

  def synopsis(assigns) do
    total = assigns.passages |> Enum.map(& &1["verses"]) |> Enum.sum() |> max(1)

    families =
      assigns.passages
      |> Enum.group_by(& &1["family"])
      |> Enum.map(fn {family, passages} ->
        {family, passages |> Enum.map(& &1["verses"]) |> Enum.sum()}
      end)
      |> Enum.sort_by(&(-elem(&1, 1)))

    assigns =
      assign(assigns,
        segments: segments(assigns.passages, total),
        families: families,
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
            class={["seg", "f-" <> segment.family]}
            style={"flex-grow: #{segment.verses}"}
            title={segment.title}
          >
            <span :if={segment.label}>{segment.label}</span>
          </span>
        <% end %>
      </div>
      <ul class="legend">
        <li :for={{family, verses} <- @families}>
          <i class={"sw f-" <> family}></i><b>{PlayLabels.verse_family_label(family)}</b>
          {number(verses)} vv. · {percent(verses, @total)}
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
              <i class={"sw f-" <> passage["family"]}></i>{PlayLabels.verse_form_label(
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
        family: passage["family"],
        verses: passage["verses"],
        title: "#{label} · vv. #{range(passage)} · #{passage["verses"]} verses",
        label: if(passage["verses"] / total > 0.06, do: label)
      }
    end)
  end

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
              <th></th>
              <th
                :for={{column, i} <- Enum.with_index(@columns)}
                scope="col"
                title={column_title(column)}
                class={act_start(@columns, i)}
              >
                <i :if={column["family"]} class={"sw f-" <> column["family"]}></i>
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
    do: "#{PlayLabels.verse_form_label(form)} · vv. #{range(column)}"

  defp column_title(%{"act" => act, "label" => label}) when is_integer(act),
    do: "#{Edition.roman(act)}: #{label}"

  defp column_title(%{"label" => label}), do: label || ""

  defp act_start(columns, i),
    do:
      if(i > 0 and Enum.at(columns, i - 1)["act"] != Enum.at(columns, i)["act"], do: "act-start")
end
