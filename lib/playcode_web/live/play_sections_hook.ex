defmodule PlaycodeWeb.PlaySectionsHook do
  @moduledoc """
  Assigns `:play_counts`, the counts the sidebar shows beside a play's sections, on a page
  that names its play in `:play_context`. They are read again after every event, so a row
  a tab adds or deletes is counted at once. Also `:play_live`, the play's entry in the live
  site (`SiteStatus.live/1`), empty when it is not there, read again when a build or
  deploy ends.
  """
  import Phoenix.Component
  import Phoenix.LiveView

  alias Playcode.Catalogue
  alias Playcode.Export.{SiteBuilder, SiteStatus}

  def on_mount(:default, _params, _session, socket) do
    {:cont,
     socket
     |> assign(play_counts: nil, play_live: %{}, play_site_listening: false)
     |> attach_hook(:play_counts, :handle_params, fn _params, _uri, socket ->
       {:cont, socket |> count() |> live_entry()}
     end)
     # ponytail: one count query per event, keystroke validations included; skip those
     # if it ever shows in the timings.
     |> attach_hook(:play_counts_event, :handle_event, fn _event, _params, socket ->
       if socket.assigns[:play_context], do: send(self(), :count_play_sections)
       {:cont, socket}
     end)
     |> attach_hook(:play_counts_info, :handle_info, fn
       :count_play_sections, socket ->
         {:halt, count(socket)}

       {:site_builder, :done, _job, _result}, %{assigns: %{play_site_listening: true}} = socket ->
         {:halt, live_entry(socket)}

       message, %{assigns: %{play_site_listening: true}} = socket
       when elem(message, 0) in [:site_builder, :play_changed] ->
         {:halt, socket}

       _message, socket ->
         {:cont, socket}
     end)}
  end

  defp count(%{assigns: %{play_context: %{play: play}}} = socket),
    do: assign(socket, :play_counts, Catalogue.section_counts(play.id))

  defp count(socket), do: socket

  defp live_entry(%{assigns: %{play_context: %{play: play}}} = socket) do
    socket
    |> listen_to_site()
    |> assign(:play_live, Map.take(SiteStatus.live(), [play.code]))
  end

  defp live_entry(socket), do: socket

  defp listen_to_site(%{assigns: %{play_site_listening: false}} = socket) do
    if connected?(socket), do: SiteBuilder.subscribe()
    assign(socket, :play_site_listening, connected?(socket))
  end

  defp listen_to_site(socket), do: socket
end
