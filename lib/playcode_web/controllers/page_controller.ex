defmodule PlaycodeWeb.PageController do
  @moduledoc false

  use PlaycodeWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
