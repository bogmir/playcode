defmodule PlaycodeWeb.Admin.PlayCompareLive do
  @moduledoc """
  /admin/plays/:id/compare: the public comparison inside the play's admin tabs, drafts
  included (*Lectura paralela*), and, with `?view=pairs`, the pair review: how
  `Playcode.Alignment` pairs a translation's or version's speeches with its original's,
  row by row (*Revisión de pares*, problem 5 step 5).
  """

  use PlaycodeWeb, :live_view

  import PlaycodeWeb.Components.PlayText

  alias Playcode.{Alignment, Catalogue, PlayContent}
  alias Playcode.Alignment.Review
  alias Playcode.PlayContent.{Element, InlineMarkup}
  alias PlaycodeWeb.PlayComparison

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    play = Catalogue.get_play_with_all!(id)
    family = PlayComparison.build_family(play)

    # Both views load whole plays, so they are built once, for the live connection: the
    # first HTML is the page's frame.
    {:ok,
     socket
     |> assign(:page_title, gettext("Compare: %{title}", title: play.title))
     |> assign(:play, play)
     |> assign(:panels, [])
     |> assign(:family, family)
     |> PlayComparison.assign_display_defaults()
     |> assign(:play_context, %{play: play, active_tab: :compare})}
  end

  @impl true
  def handle_params(%{"view" => "pairs"} = params, _uri, socket) do
    %{play: play, family: family} = socket.assigns
    # The page's own play first, so it is the default when it is a translation or version;
    # only plays whose original the family holds, so an archived original is not reviewed.
    shown = [play | family]
    ids = MapSet.new(shown, & &1.id)
    candidates = Enum.filter(shown, &(&1.parent_play_id in ids && Alignment.paired?(&1)))
    chosen = Enum.find(candidates, &(&1.id == params["translation"])) || List.first(candidates)

    {:noreply,
     socket
     |> assign(view: :pairs, candidates: candidates)
     |> review(chosen)}
  end

  def handle_params(_params, _uri, socket) do
    %{play: play, family: family, panels: panels} = socket.assigns

    panels =
      if panels == [] and connected?(socket),
        do: PlayComparison.build_initial_panels(play, family),
        else: panels

    {:noreply, assign(socket, view: :side, panels: panels)}
  end

  # The review of `chosen`, worked out once it changes, after the page appears; it opens
  # on the doubtful rows.
  defp review(%{assigns: %{chosen: same}} = socket, same) when same != nil, do: socket

  defp review(socket, nil), do: assign(socket, chosen: nil, review: nil)

  defp review(socket, chosen) do
    socket
    |> assign(chosen: chosen, doubtful: true)
    |> assign_async(:review, fn ->
      rows =
        Review.rows(
          PlayContent.load_play_content(chosen.parent_play_id),
          PlayContent.load_play_content(chosen.id)
        )

      {:ok, %{review: %{rows: rows, entries: first_entries(chosen.id)}}}
    end)
  end

  # Each character's first line on the Elenco tab, where its original is corrected.
  defp first_entries(play_id) do
    for list <- PlayContent.list_cast_lists(play_id),
        entry <- list.entries,
        entry.character_id,
        reduce: %{} do
      acc -> Map.put_new(acc, entry.character_id, entry.id)
    end
  end

  @impl true
  def handle_event("toggle_doubtful", _params, socket),
    do: {:noreply, update(socket, :doubtful, &(!&1))}

  def handle_event("pick_translation", %{"translation" => id}, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/admin/plays/#{socket.assigns.play.id}/compare?#{[view: "pairs", translation: id]}"
     )}
  end

  def handle_event("add_play", %{"id" => ""}, socket), do: {:noreply, socket}

  def handle_event("add_play", %{"id" => play_id}, socket) do
    case PlayComparison.add_panel(socket.assigns.panels, play_id, socket.assigns.family) do
      {:ok, panels} ->
        {:noreply, assign(socket, :panels, panels)}

      {:error, :not_offered} ->
        {:noreply, socket}

      {:error, :max_reached} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Maximum %{max} plays allowed.", max: PlayComparison.max_panels())
         )}
    end
  end

  def handle_event("remove_panel", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)
    {:noreply, assign(socket, :panels, PlayComparison.remove_panel(socket.assigns.panels, index))}
  end

  def handle_event(event, _params, socket) do
    case PlayComparison.toggle_key(event) do
      nil -> {:noreply, socket}
      key -> {:noreply, assign(socket, key, !socket.assigns[key])}
    end
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(
        assigns,
        :available,
        PlayComparison.available_plays(assigns.family, assigns.panels)
      )

    ~H"""
    <div class="mx-auto max-w-full px-4 py-4">
      <nav class="tabs tabs-border mb-4" aria-label={gettext("Comparison views")}>
        <.link
          patch={~p"/admin/plays/#{@play.id}/compare"}
          class={["tab", @view == :side && "tab-active"]}
          aria-current={@view == :side && "page"}
        >
          {gettext("Side by side")}
        </.link>
        <.link
          patch={~p"/admin/plays/#{@play.id}/compare?view=pairs"}
          class={["tab", @view == :pairs && "tab-active"]}
          aria-current={@view == :pairs && "page"}
        >
          {gettext("Pair review")}
        </.link>
      </nav>

      <p :if={@view == :pairs && !@chosen} class="text-sm text-base-content/70">
        {gettext("No translation or version of this play to review.")}
      </p>
      <.async_result :let={review} :if={@view == :pairs && @chosen} assign={@review}>
        <:loading>
          <p class="text-sm text-base-content/70">{gettext("Loading…")}</p>
        </:loading>
        <.pair_review
          candidates={@candidates}
          chosen={@chosen}
          rows={review.rows}
          entries={review.entries}
          doubtful={@doubtful}
        />
      </.async_result>

      <div :if={@view == :side}>
        <%!-- Toolbar --%>
        <div class="mb-4 flex flex-wrap items-center gap-4 rounded-box border border-base-300 bg-base-100 px-4 py-2 shadow-sm">
          <span class="text-xs font-semibold text-base-content/70">{gettext("Display")}</span>
          <label class="flex items-center gap-1.5 text-xs cursor-pointer">
            <input
              type="checkbox"
              checked={@show_line_numbers}
              phx-click="toggle_line_numbers"
              class="checkbox checkbox-xs checkbox-primary"
            /> {gettext("Line numbers")}
          </label>
          <label class="flex items-center gap-1.5 text-xs cursor-pointer">
            <input
              type="checkbox"
              checked={@show_stage_directions}
              phx-click="toggle_stage_directions"
              class="checkbox checkbox-xs checkbox-primary"
            /> {gettext("Stage directions")}
          </label>
          <label class="flex items-center gap-1.5 text-xs cursor-pointer">
            <input
              type="checkbox"
              checked={@show_asides}
              phx-click="toggle_asides"
              class="checkbox checkbox-xs checkbox-primary"
            /> {gettext("Asides")}
          </label>
          <label class="flex items-center gap-1.5 text-xs cursor-pointer">
            <input
              type="checkbox"
              checked={@show_split_verses}
              phx-click="toggle_split_verses"
              class="checkbox checkbox-xs checkbox-primary"
            /> {gettext("Split verses")}
          </label>
          <label class="flex items-center gap-1.5 text-xs cursor-pointer">
            <input
              type="checkbox"
              checked={@show_verse_type}
              phx-click="toggle_verse_type"
              class="checkbox checkbox-xs checkbox-primary"
            /> {gettext("Verse type")}
          </label>

          <%!-- Add play --%>
          <div :if={@available != [] && length(@panels) < 4} class="ml-auto flex items-center gap-2">
            <form phx-change="add_play" class="inline">
              <select
                name="id"
                class="select select-xs select-bordered w-64"
                aria-label={gettext("Add play to compare...")}
              >
                <option value="">{gettext("Add play to compare...")}</option>
                <option :for={p <- @available} value={p.id}>
                  {p.title} ({p.code})
                </option>
              </select>
            </form>
          </div>
        </div>

        <p :if={@panels == []} class="text-sm text-base-content/70">{gettext("Loading…")}</p>
        <%!-- N-panel comparison --%>
        <div
          id="sync-scroll"
          phx-hook="SyncScroll"
          class={"grid #{PlayComparison.grid_class(length(@panels))} gap-4"}
        >
          <div
            :for={{panel, idx} <- Enum.with_index(@panels)}
            class="flex flex-col rounded-box border border-base-300 bg-base-100 shadow-sm"
          >
            <div class="sticky top-0 z-10 border-b border-base-300 bg-base-100/95 backdrop-blur-sm px-4 py-2">
              <div class="flex items-center gap-2">
                <span class={[
                  "badge badge-sm",
                  if(idx == 0, do: "badge-ghost", else: "badge-primary")
                ]}>
                  {idx + 1}
                </span>
                <span class="text-sm font-semibold truncate flex-1">{panel.play.title}</span>
                <button
                  :if={length(@panels) > 1}
                  phx-click="remove_panel"
                  phx-value-index={idx}
                  class="btn btn-ghost btn-xs btn-circle text-base-content/70 hover:text-error"
                  title={gettext("Remove")}
                >
                  <.icon name="hero-x-mark-micro" class="size-3.5" />
                </button>
              </div>
              <p class="text-xs text-base-content/70 truncate">
                {panel.play.author_name} — {panel.play.code}
              </p>
            </div>
            <div
              class="overflow-y-auto px-4 py-4 compare-panel"
              tabindex="0"
              role="region"
              aria-label={panel.play.title}
              data-panel={"panel-#{idx}"}
              style={PlayComparison.panel_height(length(@panels))}
            >
              <.play_body
                divisions={panel.divisions}
                show_line_numbers={@show_line_numbers}
                show_stage_directions={@show_stage_directions}
                show_asides={@show_asides}
                show_split_verses={@show_split_verses}
                show_verse_type={@show_verse_type}
                sync_keys={true}
              />
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :candidates, :list, required: true
  attr :chosen, :any, required: true
  attr :rows, :list, required: true
  attr :entries, :map, required: true
  attr :doubtful, :boolean, required: true

  defp pair_review(assigns) do
    rows =
      Enum.zip_with(assigns.rows || [], [nil | assigns.rows || []], fn row, above ->
        Map.put(row, :repeat, repeat?(row, above))
      end)

    assigns =
      assign(assigns,
        counts: Enum.frequencies_by(rows, & &1.kind),
        long: Enum.count(rows, & &1.long),
        shown: shown_rows(rows, assigns.doubtful)
      )

    ~H"""
    <section aria-label={gettext("Pair review")}>
      <div>
        <form phx-change="pick_translation" class="mb-3">
          <label for="pair-translation" class="text-sm font-medium mr-2">
            {gettext("Translation or version")}
          </label>
          <select id="pair-translation" name="translation" class="select select-sm select-bordered">
            <option :for={p <- @candidates} value={p.id} selected={p.id == @chosen.id}>
              {InlineMarkup.plain(p.title)} ({p.code})
            </option>
          </select>
        </form>
        <ul class="mb-3 flex flex-wrap gap-2 text-xs">
          <li
            :for={kind <- [:same, :split, :other, :added, :cut]}
            id={"pair-count-#{kind}"}
            class={["rounded px-2 py-1", kind_class(kind)]}
            title={kind_meaning(kind)}
          >
            {kind_label(kind)}: {Map.get(@counts, kind, 0)}
          </li>
          <li id="pair-count-long" class="rounded px-2 py-1 bg-warning/20">
            {gettext("Very different length")}: {@long}
          </li>
        </ul>
        <label class="mb-3 flex items-center gap-2 text-sm cursor-pointer">
          <input
            type="checkbox"
            name="doubtful"
            checked={@doubtful}
            phx-click="toggle_doubtful"
            class="checkbox checkbox-sm"
          />
          {gettext("Only the doubtful rows, with one row either side")}
        </label>
        <div class="overflow-x-auto" tabindex="0" role="region" aria-label={gettext("Pairs")}>
          <table class="table table-xs">
            <thead>
              <tr>
                <th>{gettext("Row")}</th>
                <th>{gettext("Where")}</th>
                <th>{gettext("Original")}</th>
                <th>{gettext("Pairing")}</th>
                <th>{gettext("Translation")}</th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={{row, n} <- @shown}
                id={"pair-row-#{n}"}
                class={kind_class(row.kind)}
              >
                <td class="text-base-content/70">{n}</td>
                <td class="whitespace-nowrap">{Enum.map_join(row.place, ", ", &place_label/1)}</td>
                <td>
                  <span :if={row.repeat} class="text-base-content/70 italic">
                    ↑ {gettext("Same speech as above")}
                  </span>
                  <.speech_cell :if={!row.repeat} speech={row.original} />
                </td>
                <td class="whitespace-nowrap">
                  {kind_label(row.kind)}
                  <span :if={row.long} class="badge badge-warning badge-xs">
                    {gettext("Very different length")}
                  </span>
                </td>
                <td>
                  <.speech_cell
                    speech={row.translation}
                    href={elenco_link(row.translation, @chosen, @entries)}
                  />
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </section>
    """
  end

  # The rows with their numbers; with `doubtful`, only those beside a doubtful one.
  defp shown_rows(rows, false), do: Enum.with_index(rows, 1)

  defp shown_rows(rows, true) do
    doubtful = Enum.map(rows, &(&1.kind != :same or &1.long))
    near = Enum.zip([[false | doubtful], doubtful, tl(doubtful ++ [false])])

    rows
    |> Enum.with_index(1)
    |> Enum.zip(near)
    |> Enum.filter(fn {_, flags} -> true in Tuple.to_list(flags) end)
    |> Enum.map(&elem(&1, 0))
  end

  defp repeat?(%{original: %{id: id}}, %{original: %{id: id}}), do: true
  defp repeat?(_row, _above), do: false

  defp elenco_link(nil, _play, _entries), do: nil

  defp elenco_link(speech, play, entries) do
    with %{id: id} <- speech |> Element.characters() |> List.first(),
         entry when entry != nil <- entries[id],
         do: ~p"/admin/plays/#{play.id}/content#entry-#{entry}"
  end

  attr :speech, :any, required: true
  attr :href, :string, default: nil

  defp speech_cell(%{speech: nil} = assigns), do: ~H""

  defp speech_cell(assigns) do
    text = assigns.speech |> Review.spoken_text() |> InlineMarkup.plain()
    hover = if String.length(text) > 120, do: String.slice(text, 0, 120) <> "…", else: text
    line = Review.first_line(assigns.speech)

    assigns =
      assign(assigns,
        hover: hover,
        opening: text |> String.split() |> Enum.take(8) |> Enum.join(" "),
        n: line && line.line_number
      )

    ~H"""
    <span title={@hover}>
      <span :if={@n} class="text-base-content/70">{@n}</span>
      <.link :if={@href} href={@href} class="link font-bold">
        {InlineMarkup.plain(@speech.speaker_label || "")}
      </.link>
      <b :if={!@href}>{InlineMarkup.plain(@speech.speaker_label || "")}</b>
      {@opening}
    </span>
    """
  end

  defp place_label(division),
    do:
      InlineMarkup.plain(
        division.title ||
          String.capitalize("#{division.type}#{division.number && " #{division.number}"}")
      )

  defp kind_label(:same), do: gettext("Same speaker")
  defp kind_label(:split), do: gettext("Split")
  defp kind_label(:other), do: gettext("Other speaker")
  defp kind_label(:added), do: gettext("Added")
  defp kind_label(:cut), do: gettext("Cut")

  defp kind_meaning(:same),
    do: gettext("The same character on both sides, matched in order. Almost always right.")

  defp kind_meaning(:split),
    do:
      gettext(
        "An extra speech of the translation by the same character as the original speech it goes with: a speaker repeated after a stage direction."
      )

  defp kind_meaning(:other),
    do:
      gettext(
        "Different characters, where the texts disagree on who speaks; paired by position. A renamed role, or a mistake."
      )

  defp kind_meaning(:added),
    do: gettext("A speech of the translation with nothing in the original.")

  defp kind_meaning(:cut),
    do:
      gettext(
        "A speech of the original no speech of the translation goes with. Beside another speaker, often a moved line rather than a cut."
      )

  defp kind_class(:same), do: nil
  defp kind_class(:split), do: "bg-info/10"
  defp kind_class(:other), do: "bg-warning/20"
  defp kind_class(:added), do: "bg-error/10"
  defp kind_class(:cut), do: "bg-base-200 text-base-content/70"
end
