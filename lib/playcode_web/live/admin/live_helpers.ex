defmodule PlaycodeWeb.Admin.LiveHelpers do
  @moduledoc """
  What the admin play tabs share.
  """

  use Gettext, backend: PlaycodeWeb.Gettext

  import Phoenix.LiveView, only: [put_flash: 3]

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
end
