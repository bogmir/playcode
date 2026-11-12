defmodule PlaycodeWeb.BrandingTest do
  @moduledoc """
  The application is Playcode; EMOTHE and ARTELOPE are the digital libraries it
  publishes. Chrome that names the application says Playcode, and copy that
  names the libraries keeps their brands. The UI renders in Spanish by default,
  so the assertions are in Spanish.
  """
  use PlaycodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playcode.TestFixtures

  # The home page and the catalogue that said this are gone (2026-11-12): the published site
  # is the catalogue, and the log-in page is the first a visitor sees.
  test "the login page names the platform", %{conn: conn} do
    html = conn |> get(~p"/users/log-in") |> html_response(200)

    assert html =~ "Iniciar sesión en Playcode"

    assert html |> LazyHTML.from_document() |> LazyHTML.query("title") |> LazyHTML.text() =~
             "Playcode"

    # The navbar wordmark used to read EMOTHE.
    refute html =~ ~r/>\s*EMOTHE\s*</
  end

  test "the accept-invite page welcomes the user to the platform", %{conn: conn} do
    {_user, token} = invited_user_fixture()

    {:ok, _view, html} = live(conn, ~p"/users/accept-invite/#{token}")

    assert html =~ "Bienvenido a Playcode"
  end

  test "pages carry the Playcode icon, not Phoenix's", %{conn: conn} do
    page = conn |> get(~p"/users/log-in") |> html_response(200) |> LazyHTML.from_document()

    assert page |> LazyHTML.query(~s(link[rel="icon"][href^="/images/logo.svg"])) |> Enum.count() ==
             1

    # The opening path of the Phoenix bird that `mix phx.new` ships as logo.svg.
    refute File.read!("priv/static/images/logo.svg") =~ "m26.371 33.477"
  end
end
