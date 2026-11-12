defmodule PlaycodeWeb.LocaleControllerTest do
  use PlaycodeWeb.ConnCase, async: true

  defp page_lang(conn, path) do
    [lang] =
      Regex.run(~r/<html lang="([^"]+)"/, html_response(get(conn, path), 200),
        capture: :all_but_first
      )

    lang
  end

  test "switching locale sends you back to the page you were on, now in that language",
       %{conn: conn} do
    conn = post(conn, ~p"/locale", %{locale: "en", return_to: "/users/log-in?return=1"})

    assert redirected_to(conn) == "/users/log-in?return=1"
    assert page_lang(recycle(conn), "/users/log-in") == "en"
  end

  test "without a return path it sends you home", %{conn: conn} do
    conn = post(conn, ~p"/locale", %{locale: "en"})
    assert redirected_to(conn) == "/"
  end

  test "a return path on another host sends you home instead", %{conn: conn} do
    for return_to <- ["https://evil.com", "//evil.com", "/\\evil.com"] do
      conn = post(conn, ~p"/locale", %{locale: "en", return_to: return_to})
      assert redirected_to(conn) == "/", "return_to #{inspect(return_to)}"
    end
  end

  test "an unknown locale leaves the language alone", %{conn: conn} do
    conn = post(conn, ~p"/locale", %{locale: "xx", return_to: "/users/log-in"})

    assert redirected_to(conn) == "/users/log-in"
    assert page_lang(recycle(conn), "/users/log-in") == "es"
  end
end
