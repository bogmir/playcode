defmodule PlaycodeWeb.PlayShowLive do
  @moduledoc """
  /plays/:code: a play's text, statistics and notes, with its metadata, places and
  bibliography, as the published site will show it: staff's preview, draft or complete.
  """

  use PlaycodeWeb, :live_view

  import PlaycodeWeb.Components.PlayText
  import PlaycodeWeb.Components.StatisticsPanel

  alias Playcode.Bibliography
  alias Playcode.Bibliography.Citation
  alias Playcode.Catalogue
  alias Playcode.Catalogue.{Paratext, Play}
  alias Playcode.Outline
  alias Playcode.PlayContent
  alias Playcode.PlayContent.{Element, InlineMarkup, Note, SplitVerses}
  alias Playcode.Performances
  alias Playcode.Places
  alias Playcode.Places.Authority
  alias Playcode.Statistics
  alias Playcode.Witnesses
  alias PlaycodeWeb.PlayLabels

  @impl true
  def mount(%{"code" => code}, _session, socket) do
    play =
      Catalogue.get_play_by_code_with_all!(code)

    divisions = PlayContent.load_play_content(play.id, variants: play.show_variants)
    characters = PlayContent.list_characters(play.id)
    statistic = Statistics.get_statistics(play.id)
    bibliography = Bibliography.list_for_play(play.id)
    gazetteer = Places.gazetteer()
    locale = Gettext.get_locale(PlaycodeWeb.Gettext)

    performances =
      play.id
      |> Performances.list_for_play()
      |> Performances.listing(characters, gazetteer, locale)

    %{metadata: metadata_sections, play: play_sections} =
      build_sections_navigation(play, divisions, performances, bibliography)

    {:ok,
     socket
     |> assign(:page_title, play.title)
     |> assign(:play, play)
     |> assign(:divisions, divisions)
     |> assign(:statistic, statistic)
     |> assign(:performances, performances)
     |> assign(:bibliography, bibliography)
     |> assign(:notes, divisions |> note_entries() |> Enum.reject(&Note.variant?(&1.note)))
     |> assign(:note_type, nil)
     |> assign(:metadata_sections, metadata_sections)
     |> assign(:play_sections, play_sections)
     |> assign(:gazetteer, gazetteer)
     |> assign(:locale, locale)
     |> assign(:show_line_numbers, true)
     |> assign(:show_stage_directions, true)
     |> assign(:show_asides, true)
     |> assign(:show_verse_type, false)
     |> assign(:show_variants, true)
     |> assign(:has_variants, divisions |> Note.reading_order() |> Enum.any?(&Note.variant?/1))
     |> assign(:show_folio, false)
     |> assign(:has_folio, Element.folio_passages?(divisions))
     |> assign(:show_rs, false)
     |> assign(:has_rs, Element.tagged_names?(divisions))
     |> assign(:shade_shared, false)
     |> assign(:has_shared_lines, Element.shared_lines?(divisions))
     |> assign(:leads, divisions |> Element.verse_lines() |> SplitVerses.leads())
     |> assign(:shade_stage, false)
     |> assign(:has_stage_directions, Element.stage_directions?(divisions))
     |> assign(:active_tab, :text)
     |> assign(:breadcrumbs, [
       %{label: play.title, to: ~p"/admin/plays/#{play.id}"},
       %{label: gettext("Preview")}
     ])}
  end

  @impl true
  def handle_event("toggle_line_numbers", _, socket) do
    {:noreply, assign(socket, :show_line_numbers, !socket.assigns.show_line_numbers)}
  end

  def handle_event("toggle_stage_directions", _, socket) do
    {:noreply, assign(socket, :show_stage_directions, !socket.assigns.show_stage_directions)}
  end

  def handle_event("toggle_asides", _, socket) do
    {:noreply, assign(socket, :show_asides, !socket.assigns.show_asides)}
  end

  def handle_event("toggle_shared_lines", _, socket) do
    {:noreply, assign(socket, :shade_shared, !socket.assigns.shade_shared)}
  end

  def handle_event("toggle_stage_highlight", _, socket) do
    {:noreply, assign(socket, :shade_stage, !socket.assigns.shade_stage)}
  end

  def handle_event("toggle_verse_type", _, socket) do
    {:noreply, assign(socket, :show_verse_type, !socket.assigns.show_verse_type)}
  end

  def handle_event("toggle_variants", _, socket) do
    {:noreply, assign(socket, :show_variants, !socket.assigns.show_variants)}
  end

  def handle_event("toggle_rs", _, socket) do
    {:noreply, assign(socket, :show_rs, !socket.assigns.show_rs)}
  end

  def handle_event("toggle_folio", _, socket) do
    {:noreply, assign(socket, :show_folio, !socket.assigns.show_folio)}
  end

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, String.to_existing_atom(tab))}
  end

  def handle_event("filter_notes", %{"type" => type}, socket) do
    {:noreply, assign(socket, :note_type, if(type == "", do: nil, else: type))}
  end

  # The note's id came from the browser: only one of this play's notes is scrolled to.
  def handle_event("show_note", %{"id" => id}, socket) do
    if Enum.any?(socket.assigns.notes, &(&1.note.id == id)) do
      {:noreply,
       socket
       |> assign(:active_tab, :text)
       |> push_event("scroll-to", %{id: "nref-" <> id})}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="play-text-page min-h-screen">
      <div class="max-w-7xl mx-auto px-4 py-6 lg:grid lg:grid-cols-[16rem_minmax(0,1fr)] lg:gap-6">
        <%!-- Sidebar --%>
        <aside
          id="play-sections-panel"
          class="mb-4 lg:mb-0 lg:sticky lg:top-16 lg:self-start lg:max-h-[calc(100vh-5rem)] lg:overflow-y-auto"
        >
          <%!-- Folded on a phone, open on a wide screen (F1). --%>
          <div
            id="play-contents"
            class="fold rounded-box border border-base-300 bg-base-100/90 lg:backdrop-blur-sm shadow-sm"
          >
            <div class="flex items-center justify-between px-3 py-2.5">
              <button
                type="button"
                phx-click={JS.toggle_class("flipped", to: "#play-contents")}
                aria-controls="scroll-spy-nav"
                class="flex items-center gap-2 text-sm font-semibold text-primary cursor-pointer"
              >
                <.icon name="hero-list-bullet-micro" class="size-4" /> {gettext("Contents")}
                <.icon name="hero-chevron-up-down-micro" class="size-4 text-base-content/70" />
              </button>
            </div>

            <div
              id="scroll-spy-nav"
              phx-hook="ScrollSpy"
              class="fold-body border-t border-base-300 max-h-[65vh] overflow-y-auto px-2 py-2 space-y-3"
            >
              <%!-- View switcher --%>
              <section>
                <h3 class="px-2 pt-1 text-xs font-semibold uppercase tracking-widest text-base-content/70">
                  {gettext("View")}
                </h3>
                <nav class="mt-1 space-y-px">
                  <button
                    :for={
                      {tab_key, tab_label} <-
                        [{:text, gettext("Text")}, {:statistics, gettext("Statistics")}] ++
                          if(@notes != [], do: [{:notes, gettext("Notes")}], else: [])
                    }
                    phx-click="switch_tab"
                    phx-value-tab={tab_key}
                    class={[
                      "w-full text-left block rounded-md px-2 py-1 text-xs transition-colors",
                      if(@active_tab == tab_key,
                        do: "bg-primary/10 text-primary font-medium",
                        else: "text-base-content/70 hover:bg-primary/10 hover:text-primary"
                      )
                    ]}
                  >
                    {tab_label}
                  </button>
                </nav>
              </section>

              <section :if={@active_tab == :text && @metadata_sections != []}>
                <h3 class="px-2 pt-1 text-xs font-semibold uppercase tracking-widest text-base-content/70">
                  {gettext("Metadata")}
                </h3>
                <nav class="mt-1 space-y-px">
                  <a
                    :for={section <- @metadata_sections}
                    href={"##{section.id}"}
                    class="block rounded-md px-2 py-1 text-xs text-base-content/70 transition-colors hover:bg-primary/10 hover:text-primary active:bg-primary/20"
                  >
                    {section.label}
                  </a>
                </nav>
              </section>

              <section :if={@active_tab == :text && @play_sections != []}>
                <h3 class="px-2 pt-1 text-xs font-semibold uppercase tracking-widest text-base-content/70">
                  {gettext("Sections")}
                </h3>
                <nav class="mt-1 space-y-px">
                  <a
                    :for={section <- @play_sections}
                    href={"##{section.id}"}
                    class="block rounded-md py-1 text-xs text-base-content/70 transition-colors hover:bg-primary/10 hover:text-primary active:bg-primary/20"
                    style={"padding-left: #{0.5 + section.depth * 0.625}rem"}
                  >
                    {section.label}
                  </a>
                </nav>
              </section>
            </div>

            <%!-- Visual markers (text view only) --%>
            <div
              :if={@active_tab == :text}
              class="fold-body border-t border-base-300 px-3 py-2.5 space-y-2"
            >
              <h3 class="text-xs font-semibold uppercase tracking-widest text-base-content/70">
                {gettext("Visual markers")}
              </h3>
              <label class="flex items-center gap-2 text-xs cursor-pointer text-base-content/70">
                <input
                  type="checkbox"
                  checked={@show_line_numbers}
                  phx-click="toggle_line_numbers"
                  class="checkbox checkbox-xs checkbox-primary"
                /> {gettext("Line numbers")}
              </label>
              <label class="flex items-center gap-2 text-xs cursor-pointer text-base-content/70">
                <input
                  type="checkbox"
                  checked={@show_stage_directions}
                  phx-click="toggle_stage_directions"
                  class="checkbox checkbox-xs checkbox-primary"
                /> {gettext("Stage directions")}
              </label>
              <label class="flex items-center gap-2 text-xs cursor-pointer text-base-content/70">
                <input
                  type="checkbox"
                  checked={@show_asides}
                  phx-click="toggle_asides"
                  class="checkbox checkbox-xs checkbox-primary"
                /> {gettext("Asides")}
              </label>
              <label class="flex items-center gap-2 text-xs cursor-pointer text-base-content/70">
                <input
                  type="checkbox"
                  checked={@show_verse_type}
                  phx-click="toggle_verse_type"
                  class="checkbox checkbox-xs checkbox-primary"
                /> {gettext("Verse type")}
              </label>
              <label
                :if={@has_variants}
                class="flex items-center gap-2 text-xs cursor-pointer text-base-content/70"
              >
                <input
                  type="checkbox"
                  checked={@show_variants}
                  phx-click="toggle_variants"
                  class="checkbox checkbox-xs checkbox-primary"
                /> {gettext("Variants")}
              </label>
              <label
                :if={@has_folio}
                class="flex items-center gap-2 text-xs cursor-pointer text-base-content/70"
              >
                <input
                  type="checkbox"
                  checked={@show_folio}
                  phx-click="toggle_folio"
                  class="checkbox checkbox-xs checkbox-primary"
                /> {gettext("Folio interpolations")}
              </label>
              <label
                :if={@has_rs}
                class="flex items-center gap-2 text-xs cursor-pointer text-base-content/70"
              >
                <input
                  type="checkbox"
                  checked={@show_rs}
                  phx-click="toggle_rs"
                  class="checkbox checkbox-xs checkbox-primary"
                /> {gettext("Tagged names")}
              </label>
            </div>

            <%!-- Highlight and step through (questions 45, 52) --%>
            <div
              :if={@active_tab == :text && (@has_shared_lines || @has_stage_directions)}
              class="fold-body border-t border-base-300 px-3 py-2.5 space-y-2"
            >
              <h3 class="text-xs font-semibold uppercase tracking-widest text-base-content/70">
                {gettext("Highlight")}
              </h3>
              <div :if={@has_shared_lines}>
                <label class="flex items-center gap-2 text-xs cursor-pointer text-base-content/70">
                  <input
                    type="checkbox"
                    id="shared-lines-switch"
                    checked={@shade_shared}
                    phx-click="toggle_shared_lines"
                    class="checkbox checkbox-xs checkbox-primary"
                  /> {gettext("Shared lines")}
                </label>
                <.stepper
                  :if={@shade_shared}
                  id="step-shared"
                  selector="#play-tab-text [data-part=I]"
                  previous={gettext("Previous shared line")}
                  next={gettext("Next shared line")}
                  switches={text_switches(assigns)}
                />
                <ul
                  :if={@shade_shared}
                  id="shared-legend"
                  class="pl-6 space-y-0.5 text-xs text-base-content/70"
                >
                  <li :for={
                    {part, label} <- [
                      {"I", gettext("First part")},
                      {"M", gettext("Middle part")},
                      {"F", gettext("Last part")}
                    ]
                  }>
                    <i class="shared-swatch" data-part={part}></i>{label}
                  </li>
                </ul>
              </div>
              <div :if={@has_stage_directions}>
                <label class="flex items-center gap-2 text-xs cursor-pointer text-base-content/70">
                  <input
                    type="checkbox"
                    id="sd-highlight-switch"
                    aria-label={gettext("Highlight stage directions")}
                    checked={@shade_stage}
                    phx-click="toggle_stage_highlight"
                    class="checkbox checkbox-xs checkbox-primary"
                  /> {gettext("Stage directions")}
                </label>
                <.stepper
                  :if={@shade_stage}
                  id="step-sd"
                  selector="#play-tab-text [data-sd]"
                  previous={gettext("Previous stage direction")}
                  next={gettext("Next stage direction")}
                  switches={text_switches(assigns)}
                />
              </div>
            </div>
          </div>

          <%!-- Navigation quick links --%>
          <.link
            navigate={~p"/admin/plays/#{@play.id}"}
            class="mt-2 flex items-center gap-1.5 rounded-box border border-base-300 bg-base-100/90 px-3 py-2 text-xs text-base-content/70 hover:text-primary hover:border-primary/30 transition-colors"
          >
            <.icon name="hero-pencil-square-micro" class="size-3.5" />
            {gettext("Edit in Admin")}
          </.link>
        </aside>

        <div>
          <%!-- Header --%>
          <header
            id="meta-overview"
            class="play-header mb-8 border-b border-base-300/40 pb-6 scroll-mt-20 text-center"
          >
            <p :if={@play.author_name} class="play-author">{@play.author_name}</p>
            <h1 class="play-title font-bold">{@play.title}</h1>
            <p :if={@play.original_title} class="mt-1 text-sm italic text-base-content/70">
              {@play.original_title}
            </p>

            <%!-- Relationship badge --%>
            <div :if={@play.relationship_type} class="mt-2 text-xs text-base-content/70">
              <span class="badge badge-outline badge-sm">
                {PlayLabels.relationship_type_label(@play.relationship_type)}
              </span>
              <%= if @play.parent_play do %>
                <span>
                  {gettext("of")}
                  <.link
                    navigate={~p"/plays/#{@play.parent_play.code}"}
                    class="link link-primary"
                  >
                    {@play.parent_play.title}
                  </.link>
                </span>
              <% end %>
            </div>
            <div
              :if={@play.derived_plays != []}
              class="mt-2 flex flex-wrap justify-center gap-2 text-xs text-base-content/70"
            >
              <span :for={derived <- @play.derived_plays}>
                <.link navigate={~p"/plays/#{derived.code}"} class="link link-primary">
                  {derived.title}
                </.link>
                <span :if={derived.relationship_type} class="text-base-content/70">
                  ({PlayLabels.relationship_type_label(derived.relationship_type)})
                </span>
              </span>
            </div>

            <%!-- Source info --%>
            <div :if={@play.sources != []} id="meta-sources" class="scroll-mt-20">
              <div :for={source <- @play.sources} class="mt-4 text-xs text-base-content/70">
                <p :if={source.note} class="italic"><.inline_content text={source.note} /></p>
              </div>
            </div>

            <%!-- Editors --%>
            <div
              :if={@play.editors != []}
              id="meta-editors"
              class="mt-3 flex flex-wrap justify-center gap-2 scroll-mt-20"
            >
              <span :for={editor <- @play.editors} class="text-xs text-base-content/70">
                {editor.person_name}
                <span class="text-base-content/70">
                  ({PlayLabels.editor_role_label(editor.role)})
                </span>
              </span>
            </div>

            <p class="mt-2 text-xs text-base-content/70">
              {Play.language_name(@play.language)}{" · " <> PlayLabels.form_line(@play)}
            </p>
            <p
              :if={@play.licence_url || @play.licence_text}
              class="mt-1 text-xs text-base-content/70"
            >
              <%= if @play.licence_url do %>
                <a
                  href={@play.licence_url}
                  target="_blank"
                  class="hover:text-primary transition-colors"
                >
                  {@play.licence_text || @play.licence_url}
                </a>
              <% else %>
                {@play.licence_text}
              <% end %>
            </p>
          </header>

          <%!-- Research metadata --%>
          <section
            :if={@play.historical_time || @play.composition_date_from || @play.composition_date_note}
            id="meta-study"
            class="mb-8 max-w-2xl mx-auto scroll-mt-20 text-sm"
          >
            <dl class="grid grid-cols-[max-content_1fr] gap-x-4 gap-y-1">
              <dt :if={@play.historical_time} class="text-base-content/70">
                {gettext("Historical time")}
              </dt>
              <dd :if={@play.historical_time}>
                {PlayLabels.historical_time_label(@play.historical_time)}
                <p :if={@play.historical_time_note} class="mt-1 text-xs text-base-content/70">
                  {@play.historical_time_note}
                </p>
              </dd>

              <dt
                :if={@play.composition_date_from || @play.composition_date_note}
                class="text-base-content/70"
              >
                {gettext("Composition")}
              </dt>
              <dd :if={@play.composition_date_from || @play.composition_date_note}>
                {composition_date(@play)}
                <p :if={@play.composition_date_note} class="mt-1 text-xs text-base-content/70">
                  {@play.composition_date_note}
                </p>
              </dd>
            </dl>
          </section>

          <%!-- Places --%>
          <section
            :if={@play.play_places != []}
            id="meta-places"
            class="mb-8 max-w-2xl mx-auto scroll-mt-20 text-sm"
          >
            <dl class="grid grid-cols-[max-content_1fr] gap-x-4 gap-y-2">
              <dt class="text-base-content/70">{gettext("Places")}</dt>
              <dd>
                <ul class="space-y-1">
                  <li :for={link <- sorted_places(@play.play_places)}>
                    <span>{Places.place_line(link, @gazetteer, @locale)}</span>
                    <span :if={link.role == "mentioned"} class="text-xs text-base-content/70">
                      ({PlayLabels.place_role_label(link.role)})
                    </span>
                    <span :if={link.place.is_fictional} class="badge badge-outline badge-sm">
                      {gettext("Fictional")}
                    </span>
                    <a
                      :if={Authority.url(link.place.authority, link.place.authority_id)}
                      href={Authority.url(link.place.authority, link.place.authority_id)}
                      target="_blank"
                      class="link text-xs"
                    >
                      {Authority.label(link.place.authority)}
                    </a>
                    <p :if={link.note} class="text-xs text-base-content/70">{link.note}</p>
                  </li>
                </ul>
              </dd>
            </dl>
          </section>

          <%!-- The notes on the edition (question 26), a witness list whole --%>
          <section
            :if={@play.edition_notes != []}
            id="meta-edition-notes"
            class="mb-8 max-w-2xl mx-auto scroll-mt-20 text-sm"
          >
            <dl class="grid gap-x-4 gap-y-2 sm:grid-cols-[max-content_1fr]">
              <dt class="text-base-content/70">{gettext("Notes on the edition")}</dt>
              <dd class="min-w-0 space-y-2 font-serif leading-relaxed">
                <p :for={note <- @play.edition_notes}><.inline_content text={note} /></p>
              </dd>
            </dl>
          </section>

          <%!-- Witnesses: emothe.uv.es's Testimonios, laid out like the bibliography --%>
          <section
            :if={@play.witnesses != []}
            id="meta-witnesses"
            class="mb-8 max-w-2xl mx-auto scroll-mt-20 text-sm"
          >
            <dl class="grid gap-x-4 gap-y-2 sm:grid-cols-[max-content_1fr]">
              <dt class="text-base-content/70">{gettext("Witnesses")}</dt>
              <dd class="min-w-0">
                <ul class="space-y-2">
                  <li
                    :for={witness <- @play.witnesses}
                    class="pl-6 -indent-6 font-serif leading-relaxed"
                  >
                    {Witnesses.html(witness)}
                  </li>
                </ul>
              </dd>
            </dl>
          </section>

          <%!-- Performances (layout B): a line each, their sources once below --%>
          <section
            :if={@performances.lines != []}
            id="meta-performances"
            class="mb-8 max-w-2xl mx-auto scroll-mt-20 text-sm"
          >
            <dl class="grid gap-x-4 gap-y-2 sm:grid-cols-[max-content_1fr]">
              <dt class="text-base-content/70">{gettext("Performances")}</dt>
              <dd class="min-w-0">
                <ul class="space-y-2">
                  <li :for={line <- @performances.lines}>
                    <span :if={line.date} class="font-semibold">
                      <.inline_content text={line.date} />
                    </span>
                    <.inline_content :if={line.parts != []} text={Enum.join(line.parts, " · ")} />
                    <span
                      :if={line.reference}
                      class="text-xs text-base-content/70 whitespace-nowrap"
                    >
                      {line.reference}
                    </span>
                    <p :if={line.cast != []} class="text-xs">
                      {gettext("Cast")}: <.inline_content text={Enum.join(line.cast, "; ")} />
                    </p>
                    <p :if={line.note} class="text-xs"><.inline_content text={line.note} /></p>
                  </li>
                </ul>
                <ul
                  :if={@performances.sources != []}
                  class="mt-4 pt-3 border-t border-base-300 space-y-1 font-serif leading-relaxed"
                >
                  <li
                    :for={{number, entry} <- @performances.sources}
                    class="pl-6 -indent-6 [&_a]:link [&_a]:break-all"
                  >
                    [{number}] {Citation.html(entry)}
                  </li>
                </ul>
              </dd>
            </dl>
          </section>

          <%!-- Bibliography: laid out like Study and Places, a hanging indent per citation --%>
          <section
            :if={@bibliography != []}
            id="meta-bibliography"
            class="mb-8 max-w-2xl mx-auto scroll-mt-20 text-sm"
          >
            <dl class="grid gap-x-4 gap-y-2 sm:grid-cols-[max-content_1fr]">
              <dt class="text-base-content/70">{gettext("Bibliography")}</dt>
              <dd class="min-w-0">
                <div
                  :for={{kind, subgroups} <- @bibliography}
                  id={"meta-bibliography-#{kind}"}
                  class="mb-5 last:mb-0 scroll-mt-20"
                >
                  <h3 class="mb-2 font-semibold text-base-content">
                    {PlayLabels.bibliography_kind_label(kind)}
                  </h3>
                  <div :for={{language, links} <- subgroups}>
                    <h4
                      :if={kind == "translation"}
                      class="mb-1 mt-3 text-xs uppercase tracking-wide text-base-content/70"
                    >
                      {PlayLabels.bibliography_language_label(language)}
                    </h4>
                    <ul class="space-y-2">
                      <li
                        :for={link <- links}
                        class="pl-6 -indent-6 font-serif leading-relaxed [&_a]:link [&_a]:break-all"
                      >
                        {Citation.html(link.entry, link)}
                      </li>
                    </ul>
                  </div>
                </div>
              </dd>
            </dl>
          </section>

          <%!-- Text tab --%>
          <%!-- AlignParts: site.js's EMOTHE.align, re-run after each patch (data-switches). --%>
          <div
            :if={@active_tab == :text}
            id="play-tab-text"
            phx-hook="AlignParts"
            data-switches={text_switches(assigns)}
          >
            <.play_body
              paratexts={@play.paratexts}
              divisions={@divisions}
              leads={@leads}
              show_line_numbers={@show_line_numbers}
              show_stage_directions={@show_stage_directions}
              show_asides={@show_asides}
              shade_shared={@shade_shared}
              shade_stage={@shade_stage}
              show_verse_type={@show_verse_type}
              show_variants={@show_variants}
              show_folio={@show_folio}
              show_rs={@show_rs}
            />
          </div>

          <%!-- Statistics tab --%>
          <div :if={@active_tab == :statistics} id="play-tab-statistics">
            <.stats_panel statistic={@statistic} play={@play} />
          </div>

          <%!-- Notes tab --%>
          <div :if={@active_tab == :notes} id="play-tab-notes" class="max-w-2xl mx-auto">
            <.notes_list notes={@notes} type={@note_type} />
          </div>
        </div>
      </div>
    </div>
    """
  end

  # The play's sections follow its outline: each paratext and division where it stands.
  defp build_sections_navigation(play, divisions, performances, bibliography) do
    play_sections =
      play.paratexts
      |> Outline.items(divisions)
      |> Enum.flat_map(&outline_navigation_item/1)

    %{
      metadata: build_metadata_sections(play, performances, bibliography),
      play: play_sections
    }
  end

  defp outline_navigation_item(%Paratext{} = paratext),
    do: [%{id: "paratext-#{paratext.id}", label: PlayLabels.paratext_title(paratext), depth: 0}]

  defp outline_navigation_item(division), do: division_navigation_item(division, 0)

  defp build_metadata_sections(play, performances, bibliography) do
    base = [%{id: "meta-overview", label: gettext("Overview")}]

    base
    |> maybe_add_section(
      play.historical_time != nil or play.composition_date_from != nil or
        play.composition_date_note != nil,
      "meta-study",
      gettext("Study")
    )
    |> maybe_add_section(play.play_places != [], "meta-places", gettext("Places"))
    |> maybe_add_section(play.sources != [], "meta-sources", gettext("Source"))
    |> maybe_add_section(play.editors != [], "meta-editors", gettext("Editors"))
    |> maybe_add_section(
      play.edition_notes != [],
      "meta-edition-notes",
      gettext("Notes on the edition")
    )
    |> maybe_add_section(play.witnesses != [], "meta-witnesses", gettext("Witnesses"))
    |> maybe_add_section(
      performances.lines != [],
      "meta-performances",
      gettext("Performances")
    )
    |> maybe_add_section(bibliography != [], "meta-bibliography", gettext("Bibliography"))
  end

  defp maybe_add_section(sections, true, id, label), do: sections ++ [%{id: id, label: label}]
  defp maybe_add_section(sections, false, _id, _label), do: sections

  # An en dash, collapsing when the dating is a single year. A note with no years is a
  # permitted state, and yields nothing here — the note below the value carries it.
  defp composition_date(%{composition_date_from: nil}), do: ""

  defp composition_date(%{composition_date_from: from, composition_date_to: to}) when from == to,
    do: to_string(from)

  defp composition_date(%{composition_date_from: from, composition_date_to: to}),
    do: "#{from}–#{to}"

  # Settings first, then mentions, each keeping its own curated order.
  defp sorted_places(play_places) do
    Enum.sort_by(play_places, fn link -> {link.role != "setting", link.position} end)
  end

  defp division_navigation_item(division, depth) do
    current =
      case division.title do
        title when is_binary(title) and title != "" ->
          [%{id: "div-#{division.id}", label: InlineMarkup.plain(title), depth: depth}]

        _ ->
          []
      end

    children =
      division
      |> Map.get(:children, [])
      |> Enum.flat_map(&division_navigation_item(&1, depth + 1))

    current ++ children
  end

  # The switches whose turning re-renders the play's text, for the stepper's hook.
  defp text_switches(assigns) do
    assigns
    |> Map.take(~w(show_line_numbers show_stage_directions show_asides show_verse_type
                   show_variants show_folio show_rs shade_shared shade_stage)a)
    |> Enum.map_join(" ", fn {key, on} -> "#{key}=#{on}" end)
  end

  attr :id, :string, required: true
  attr :selector, :string, required: true
  attr :previous, :string, required: true
  attr :next, :string, required: true
  attr :switches, :string, required: true

  # The arrows, the count and its live region, run by site.js's EMOTHE.stepper through the
  # Stepper hook. The count and the live region are the hook's: LiveView leaves them alone.
  # LiveView calls the hook's updated() only when this element changes, so it carries the
  # switches that re-render the text (data-switches): turning one re-counts, and puts back
  # the outline LiveView's patch drops.
  defp stepper(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="Stepper"
      data-selector={@selector}
      data-of={gettext("of")}
      data-switches={@switches}
      class={
        [
          "flex items-center gap-1 pl-6 text-xs text-base-content/70",
          # Below lg the side panel scrolls away: the arrows stay at the foot of the window.
          "max-lg:fixed max-lg:right-4 max-lg:z-30 max-lg:rounded-box max-lg:border max-lg:border-base-300 max-lg:bg-base-100 max-lg:p-1 max-lg:shadow",
          if(@id == "step-sd", do: "max-lg:bottom-16", else: "max-lg:bottom-4")
        ]
      }
    >
      <button type="button" data-step="-1" aria-label={@previous} class="btn btn-ghost btn-xs">
        ‹
      </button>
      <span
        id={@id <> "-count"}
        phx-update="ignore"
        data-step-count
        class="tabular-nums"
      >
      </span>
      <span id={@id <> "-said"} phx-update="ignore" data-step-said aria-live="polite" class="sr-only">
      </span>
      <button type="button" data-step="1" aria-label={@next} class="btn btn-ghost btn-xs">
        ›
      </button>
    </div>
    """
  end
end
