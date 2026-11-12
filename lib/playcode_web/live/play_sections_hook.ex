defmodule PlaycodeWeb.PlaySectionsHook do
  @moduledoc """
  Assigns `:play_counts`, the counts the sidebar shows beside a play's sections, on a page
  that names its play in `:play_context`. They are read again after every event, so a row
  a tab adds or deletes is counted at once. Also `:play_deployed`, the `content_version`
  the last deploy published the play with, or nil when it did not publish it.
  """
  import Phoenix.Component
  import Phoenix.LiveView

  alias Playcode.Catalogue
  alias Playcode.Export.StaticSite

  def on_mount(:default, _params, _session, socket) do
    {:cont,
     socket
     |> assign(play_counts: nil, play_deployed: nil)
     |> attach_hook(:play_counts, :handle_params, fn _params, _uri, socket ->
       {:cont, socket |> count() |> deployed()}
     end)
     # ponytail: one count query per event, keystroke validations included; skip those
     # if it ever shows in the timings.
     |> attach_hook(:play_counts_event, :handle_event, fn _event, _params, socket ->
       if socket.assigns[:play_context], do: send(self(), :count_play_sections)
       {:cont, socket}
     end)
     |> attach_hook(:play_counts_info, :handle_info, fn
       :count_play_sections, socket -> {:halt, count(socket)}
       _message, socket -> {:cont, socket}
     end)}
  end

  defp count(%{assigns: %{play_context: %{play: play}}} = socket),
    do: assign(socket, :play_counts, Catalogue.section_counts(play.id))

  defp count(socket), do: socket

  defp deployed(%{assigns: %{play_context: %{play: play}}} = socket) do
    deployed = StaticSite.output_dir() |> StaticSite.deployed_plays() |> Map.get(play.code)
    assign(socket, :play_deployed, deployed)
  end

  defp deployed(socket), do: socket
end
