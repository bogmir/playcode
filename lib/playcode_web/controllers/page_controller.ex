defmodule PlaycodeWeb.PageController do
  @moduledoc false

  use PlaycodeWeb, :controller

  # Playcode has no public page: the published site is the catalogue.
  def home(conn, _params) do
    redirect(conn,
      to: if(conn.assigns.current_user, do: ~p"/admin/plays", else: ~p"/users/log-in")
    )
  end
end
