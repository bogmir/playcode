defmodule PlaycodeWeb.FontPreloadTest do
  use PlaycodeWeb.ConnCase, async: true

  # Without a preload the fonts arrived after the first paint, and every page jerked
  # sideways as Inter replaced the narrower fallback.
  test "every page preloads the fonts it is set in, and each is served", %{conn: conn} do
    html = conn |> get(~p"/users/log-in") |> html_response(200)

    fonts =
      html
      |> LazyHTML.from_document()
      |> LazyHTML.query("link[rel=preload][as=font][crossorigin]")
      |> LazyHTML.attribute("href")

    assert "/site-fonts/inter-400-latin.woff2" in fonts
    assert "/site-fonts/source-serif-4-400-latin.woff2" in fonts
    for font <- fonts, do: assert(response(get(build_conn(), font), 200))
  end
end
