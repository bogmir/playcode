defmodule PlaycodeWeb.Admin.PlayStatisticsLive do
  @moduledoc """
  /admin/plays/:id/statistics: the play's statistics as the static site draws them, the
  encoder's check on the markup (a wrong verse form shows in the synopsis, a speech given
  to the wrong role in the table), with the date they were computed and Recompute.
  """

  use PlaycodeWeb, :live_view

  import PlaycodeWeb.Components.StatisticsPanel

  alias Playcode.Catalogue
  alias Playcode.Statistics

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    play = Catalogue.get_play!(id)

    {:ok,
     socket
     |> assign(:page_title, "#{play.title} — #{gettext("Statistics")}")
     |> assign(:play, play)
     |> assign(:statistic, Statistics.get_statistics(play.id))
     |> assign(:play_context, %{play: play, active_tab: :statistics})}
  end

  @impl true
  def handle_event("recompute_stats", _, socket) do
    statistic = Statistics.recompute(socket.assigns.play.id)

    {:noreply,
     socket |> assign(statistic: statistic) |> put_flash(:info, gettext("Statistics recomputed."))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page>
      <.page_header>
        {gettext("Statistics")}
        <:subtitle>{@play.title}</:subtitle>
        <:actions>
          <span id="computed-at" class="text-sm text-base-content/70">
            {gettext("Computed")} {Calendar.strftime(@statistic.computed_at, "%Y-%m-%d %H:%M")}
          </span>
          <button phx-click="recompute_stats" class="btn btn-sm btn-outline btn-primary">
            <.icon name="hero-arrow-path-mini" class="size-4" /> {gettext("Recompute")}
          </button>
        </:actions>
      </.page_header>
      <.stats_panel statistic={@statistic} play={@play} />
    </.page>
    """
  end
end
