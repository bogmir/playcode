defmodule PlaycodeWeb.PlayShowLive do
  @moduledoc """
  /plays/:code: a play's text, statistics and notes, with its metadata, places and
  bibliography. A draft is a 404 except for staff, who reach it from the admin pages.
  """

  use PlaycodeWeb, :live_view

  import PlaycodeWeb.Components.PlayText
  import PlaycodeWeb.Components.StatisticsPanel

  alias Playcode.Authz
  alias Playcode.Bibliography
  alias Playcode.Bibliography.Citation
  alias Playcode.Catalogue
  alias Playcode.Catalogue.Play
  alias Playcode.PlayContent
  alias Playcode.PlayContent.{Division, Note}
  alias Playcode.Places
  alias Playcode.Places.Authority
  alias Playcode.Statistics
  alias PlaycodeWeb.PlayLabels

  @impl true
  def mount(%{"code" => code}, _session, socket) do
    play =
      Catalogue.get_play_by_code_with_all!(code,
        complete: not Authz.can?(socket.assigns.current_user, :view_drafts)
      )

    divisions = PlayContent.load_play_content(play.id)
    characters = PlayContent.list_characters(play.id)
    statistic = Statistics.get_statistics(play.id)
    bibliography = Bibliography.list_for_play(play.id)

    %{metadata: metadata_sections, play: play_sections} =
      build_sections_navigation(play, divisions, bibliography)

    {:ok,
     socket
     |> assign(:page_title, play.title)
     |> assign(:play, play)
     |> assign(:divisions, divisions)
     |> assign(:characters, characters)
     |> assign(:statistic, statistic)
     |> assign(:bibliography, bibliography)
     |> assign(:notes, notes(divisions))
     |> assign(:note_type, nil)
     |> assign(:metadata_sections, metadata_sections)
     |> assign(:play_sections, play_sections)
     |> assign(:gazetteer, Places.gazetteer())
     |> assign(:locale, Gettext.get_locale(PlaycodeWeb.Gettext))
     |> assign(:show_line_numbers, true)
     |> assign(:show_stage_directions, true)
     |> assign(:show_asides, true)
     |> assign(:show_split_verses, true)
     |> assign(:show_verse_type, false)
     |> assign(:active_tab, :text)
     |> assign(:sidebar_open, true)
     |> assign(:breadcrumbs, [
       %{label: gettext("Catalogue"), to: ~p"/plays"},
       %{label: play.title}
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

  def handle_event("toggle_split_verses", _, socket) do
    {:noreply, assign(socket, :show_split_verses, !socket.assigns.show_split_verses)}
  end

  def handle_event("toggle_verse_type", _, socket) do
    {:noreply, assign(socket, :show_verse_type, !socket.assigns.show_verse_type)}
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

  def handle_event("toggle_sidebar", _, socket) do
    {:noreply, assign(socket, :sidebar_open, !socket.assigns.sidebar_open)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="play-text-page min-h-screen">
      <div class="max-w-7xl mx-auto px-4 py-6 lg:grid lg:grid-cols-[16rem_minmax(0,1fr)] lg:gap-6">
        <%!-- Sidebar --%>
        <aside id="play-sections-panel" class="mb-4 lg:mb-0 lg:sticky lg:top-16 lg:self-start">
          <div class="rounded-box border border-base-300 bg-base-100/90 backdrop-blur-sm shadow-sm">
            <div class="flex items-center justify-between px-3 py-2.5">
              <button
                phx-click="toggle_sidebar"
                class="flex items-center gap-2 text-sm font-semibold text-primary cursor-pointer"
              >
                <.icon name="hero-list-bullet-micro" class="size-4" /> {gettext("Contents")}
                <.icon
                  name={
                    if @sidebar_open,
                      do: "hero-chevron-up-micro",
                      else: "hero-chevron-down-micro"
                  }
                  class="size-4 text-base-content/40"
                />
              </button>
            </div>

            <div
              :if={@sidebar_open}
              id="scroll-spy-nav"
              phx-hook="ScrollSpy"
              class="border-t border-base-300 max-h-[65vh] overflow-y-auto px-2 py-2 space-y-3"
            >
              <%!-- View switcher --%>
              <section>
                <h3 class="px-2 pt-1 text-[10px] font-semibold uppercase tracking-widest text-base-content/40">
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
                <h3 class="px-2 pt-1 text-[10px] font-semibold uppercase tracking-widest text-base-content/40">
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
                <h3 class="px-2 pt-1 text-[10px] font-semibold uppercase tracking-widest text-base-content/40">
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
              :if={@sidebar_open && @active_tab == :text}
              class="border-t border-base-300 px-3 py-2.5 space-y-2"
            >
              <h3 class="text-[10px] font-semibold uppercase tracking-widest text-base-content/40">
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
                  checked={@show_split_verses}
                  phx-click="toggle_split_verses"
                  class="checkbox checkbox-xs checkbox-primary"
                /> {gettext("Split verses")}
              </label>
              <label class="flex items-center gap-2 text-xs cursor-pointer text-base-content/70">
                <input
                  type="checkbox"
                  checked={@show_verse_type}
                  phx-click="toggle_verse_type"
                  class="checkbox checkbox-xs checkbox-primary"
                /> {gettext("Verse type")}
              </label>
            </div>
          </div>

          <%!-- Navigation quick links --%>
          <.link
            navigate={~p"/plays"}
            class="mt-2 flex items-center gap-1.5 rounded-box border border-base-300 bg-base-100/90 px-3 py-2 text-xs text-base-content/60 hover:text-primary hover:border-primary/30 transition-colors"
          >
            <.icon name="hero-arrow-left-micro" class="size-3.5" />
            {gettext("Back to Catalogue")}
          </.link>
          <.link
            :if={assigns[:current_user]}
            navigate={~p"/admin/plays/#{@play.id}"}
            class="mt-1 flex items-center gap-1.5 rounded-box border border-base-300 bg-base-100/90 px-3 py-2 text-xs text-base-content/60 hover:text-primary hover:border-primary/30 transition-colors"
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
            <h2 class="play-author">{@play.author_name}</h2>
            <h1 class="play-title font-bold">{@play.title}</h1>
            <p :if={@play.original_title} class="mt-1 text-sm italic text-base-content/50">
              {@play.original_title}
            </p>

            <%!-- Relationship badge --%>
            <div :if={@play.relationship_type} class="mt-2 text-xs text-base-content/60">
              <span class="badge badge-outline badge-xs">
                {relationship_type_label(@play.relationship_type)}
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
              class="mt-2 flex flex-wrap justify-center gap-2 text-xs text-base-content/50"
            >
              <span :for={derived <- @play.derived_plays}>
                <.link navigate={~p"/plays/#{derived.code}"} class="link link-primary">
                  {derived.title}
                </.link>
                <span :if={derived.relationship_type} class="text-base-content/35">
                  ({relationship_type_label(derived.relationship_type)})
                </span>
              </span>
            </div>

            <%!-- Source info --%>
            <div :if={@play.sources != []} id="meta-sources" class="scroll-mt-20">
              <div :for={source <- @play.sources} class="mt-4 text-xs text-base-content/50">
                <p :if={source.note} class="italic">{source.note}</p>
              </div>
            </div>

            <%!-- Editors --%>
            <div
              :if={@play.editors != []}
              id="meta-editors"
              class="mt-3 flex flex-wrap justify-center gap-2 scroll-mt-20"
            >
              <span :for={editor <- @play.editors} class="text-xs text-base-content/50">
                {editor.person_name}
                <span class="text-base-content/35">
                  ({PlayLabels.editor_role_label(editor.role)})
                </span>
              </span>
            </div>

            <p class="mt-2 text-xs text-base-content/50">
              {Play.language_name(@play.language)}{" · " <> form_line(@play)}
            </p>
            <p
              :if={@play.licence_url || @play.licence_text}
              class="mt-1 text-xs text-base-content/40"
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
            <p class="mt-1 text-xs text-base-content/30">
              {PlaycodeWeb.Endpoint.url() <> ~p"/plays/#{@play.code}"}
            </p>
          </header>

          <%!-- Research metadata --%>
          <section
            :if={@play.historical_time || @play.composition_date_from || @play.composition_date_note}
            id="meta-study"
            class="mb-8 max-w-2xl mx-auto scroll-mt-20 text-sm"
          >
            <dl class="grid grid-cols-[max-content_1fr] gap-x-4 gap-y-1">
              <dt :if={@play.historical_time} class="text-base-content/50">
                {gettext("Historical time")}
              </dt>
              <dd :if={@play.historical_time}>
                {PlayLabels.historical_time_label(@play.historical_time)}
                <p :if={@play.historical_time_note} class="mt-1 text-xs text-base-content/60">
                  {@play.historical_time_note}
                </p>
              </dd>

              <dt
                :if={@play.composition_date_from || @play.composition_date_note}
                class="text-base-content/50"
              >
                {gettext("Composition")}
              </dt>
              <dd :if={@play.composition_date_from || @play.composition_date_note}>
                {composition_date(@play)}
                <p :if={@play.composition_date_note} class="mt-1 text-xs text-base-content/60">
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
              <dt class="text-base-content/50">{gettext("Places")}</dt>
              <dd>
                <ul class="space-y-1">
                  <li :for={link <- sorted_places(@play.play_places)}>
                    <span>{Places.breadcrumb(link.place, @gazetteer, @locale)}</span>
                    <span :if={link.role == "mentioned"} class="text-xs text-base-content/50">
                      ({PlayLabels.place_role_label(link.role)})
                    </span>
                    <span :if={link.place.is_fictional} class="badge badge-outline badge-xs">
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
                    <p :if={link.note} class="text-xs text-base-content/60">{link.note}</p>
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
              <dt class="text-base-content/50">{gettext("Bibliography")}</dt>
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
                      class="mb-1 mt-3 text-xs uppercase tracking-wide text-base-content/50"
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

          <%!-- Editorial notes (text view only) --%>
          <div
            :for={{note, index} <- Enum.with_index(@play.editorial_notes, 1)}
            :if={@active_tab == :text}
          >
            <hr :if={index > 1} class="max-w-2xl mx-auto border-base-300 mb-6" />
            <div
              id={"meta-note-#{index}"}
              class="mb-6 max-w-2xl mx-auto scroll-mt-20 text-justify text-sm"
            >
              <h3 :if={note.heading} class="font-bold text-center mb-2">{note.heading}</h3>
              <div class="whitespace-pre-line">{note.content}</div>
            </div>
          </div>

          <%!-- Text tab --%>
          <div :if={@active_tab == :text} id="play-tab-text">
            <.play_body
              divisions={@divisions}
              characters={@characters}
              show_line_numbers={@show_line_numbers}
              show_stage_directions={@show_stage_directions}
              show_asides={@show_asides}
              show_split_verses={@show_split_verses}
              show_verse_type={@show_verse_type}
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

  # Each note with the word it glosses and where it is: the division's and the scene's
  # titles, and the line's number when it has one.
  defp notes(divisions) do
    for %{note: note, anchor: anchor, division: division, scene: scene} <-
          Note.with_anchors(divisions) do
      line = if match?(%Division{}, anchor), do: nil, else: anchor.line_number

      where =
        [
          division.title,
          scene && scene.title,
          line && gettext("line %{n}", n: line)
        ]
        |> Enum.reject(&is_nil/1)
        |> Enum.join(", ")

      %{note: note, glossed: Note.glossed(note, PlayContent.anchor_text(anchor)), where: where}
    end
  end

  defp build_sections_navigation(play, divisions, bibliography) do
    metadata_sections = build_metadata_sections(play, bibliography)
    play_sections = divisions |> Enum.flat_map(&division_navigation_item(&1, 0))

    %{metadata: metadata_sections, play: play_sections}
  end

  defp build_metadata_sections(play, bibliography) do
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
    |> maybe_add_section(bibliography != [], "meta-bibliography", gettext("Bibliography"))
    |> Kernel.++(build_editorial_note_sections(play.editorial_notes))
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

  defp build_editorial_note_sections(notes) do
    notes
    |> Enum.with_index(1)
    |> Enum.map(fn {note, index} ->
      label =
        case note.heading do
          heading when is_binary(heading) and heading != "" -> heading
          _ -> "#{gettext("Editorial Note")} #{index}"
        end

      %{id: "meta-note-#{index}", label: label}
    end)
  end

  defp division_navigation_item(division, depth) do
    current =
      case division.title do
        title when is_binary(title) and title != "" ->
          [%{id: "div-#{division.id}", label: title, depth: depth}]

        _ ->
          []
      end

    children =
      division
      |> Map.get(:children, [])
      |> Enum.flat_map(&division_navigation_item(&1, depth + 1))

    current ++ children
  end

  defp relationship_type_label("traduccion"), do: gettext("Translation")
  defp relationship_type_label("adaptacion"), do: gettext("Adaptation")
  defp relationship_type_label("refundicion"), do: gettext("Reworking")
  defp relationship_type_label(_), do: ""

  defp form_line(play) do
    case {Play.form(play), play.verse_count} do
      {"prose", _} ->
        PlayLabels.form_label("prose")

      {form, n} when is_integer(n) and n > 0 ->
        "#{PlayLabels.form_label(form)} · #{n} #{gettext("verses")}"

      {form, _} ->
        PlayLabels.form_label(form)
    end
  end
end
