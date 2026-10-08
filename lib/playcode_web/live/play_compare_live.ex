defmodule PlaycodeWeb.PlayCompareLive do
  use PlaycodeWeb, :live_view

  import PlaycodeWeb.Components.PlayText

  alias Playcode.{Authz, Catalogue}
  alias PlaycodeWeb.PlayComparison

  @impl true
  def mount(%{"code" => code}, _session, socket) do
    opts = [complete: not Authz.can?(socket.assigns.current_user, :view_drafts)]
    play = Catalogue.get_play_by_code_with_all!(code, opts)
    family = PlayComparison.build_family(play, opts)
    panels = PlayComparison.build_initial_panels(play, family)

    {:ok,
     socket
     |> assign(:page_title, gettext("Compare: %{title}", title: play.title))
     |> assign(:play, play)
     |> assign(:panels, panels)
     |> assign(:family, family)
     |> PlayComparison.assign_display_defaults()
     |> assign(:breadcrumbs, [
       %{label: gettext("Catalogue"), to: ~p"/plays"},
       %{label: play.title, to: ~p"/plays/#{play.code}"},
       %{label: gettext("Comparison")}
     ])}
  end

  @impl true
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
      <%!-- Toolbar --%>
      <div class="mb-4 flex flex-wrap items-center gap-4 rounded-box border border-base-300 bg-base-100 px-4 py-2 shadow-sm">
        <.link
          navigate={~p"/plays/#{@play.code}"}
          class="btn btn-xs btn-ghost gap-1 text-base-content/60 hover:text-primary"
        >
          <.icon name="hero-arrow-left-mini" class="size-3.5" />
          {gettext("Back to play")}
        </.link>
        <span class="text-xs font-semibold text-base-content/50">{gettext("Display")}</span>
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
            <select name="id" class="select select-xs select-bordered w-64">
              <option value="">{gettext("Add play to compare...")}</option>
              <option :for={p <- @available} value={p.id}>
                {p.title} ({p.code})
              </option>
            </select>
          </form>
        </div>
      </div>

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
                class="btn btn-ghost btn-xs btn-circle text-base-content/40 hover:text-error"
                title={gettext("Remove")}
              >
                <.icon name="hero-x-mark-micro" class="size-3.5" />
              </button>
            </div>
            <p class="text-xs text-base-content/50 truncate">
              {panel.play.author_name} — {panel.play.code}
            </p>
          </div>
          <div
            class="overflow-y-auto px-4 py-4 compare-panel"
            data-panel={"panel-#{idx}"}
            style={PlayComparison.panel_height(length(@panels))}
          >
            <.play_body
              divisions={panel.divisions}
              characters={panel.characters}
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
    """
  end
end
