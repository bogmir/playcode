defmodule PlaycodeWeb.Admin.LiveHelpers do
  @moduledoc """
  What the admin pages share.
  """

  use Gettext, backend: PlaycodeWeb.Gettext

  import Phoenix.LiveView, only: [put_flash: 3]

  alias Playcode.ActivityLog

  @doc """
  Tells the user the item an event named is gone. Its id came from the browser: a
  record a double click or another tab already deleted, another play's, or no id at
  all. The caller reloads its list as well, so a stale tab catches up.
  """
  def put_gone_flash(socket) do
    put_flash(
      socket,
      :error,
      gettext("That item no longer exists. The list has been refreshed.")
    )
  end

  @doc """
  Records what the socket's user just did in the activity log. The entry belongs to the
  play it is about, when it is about a play, or else to the page's `:play`, on a play's
  tabs. Never fails the action: see `ActivityLog.log!/1`.
  """
  def log_activity(socket, action, resource_type, resource_id, metadata \\ %{}) do
    ActivityLog.log!(%{
      user_id: socket.assigns.current_user.id,
      play_id: play_id(socket, resource_type, resource_id),
      action: action,
      resource_type: resource_type,
      resource_id: resource_id,
      metadata: metadata
    })
  end

  defp play_id(_socket, "play", play_id), do: play_id
  defp play_id(%{assigns: %{play: %{id: id}}}, _type, _id), do: id
  defp play_id(_socket, _type, _id), do: nil
end
