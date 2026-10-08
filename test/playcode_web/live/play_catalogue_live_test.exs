defmodule PlaycodeWeb.PlayCatalogueLiveTest do
  use PlaycodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playcode.TestFixtures

  defp complete(attrs), do: play_fixture(Map.put(attrs, "is_complete", true))

  test "lists complete originals with their translations beneath, and no drafts",
       %{conn: conn} do
    %{original: original, translation: translation} = translation_family_fixture()
    draft = play_fixture(%{"title" => "Borrador sin terminar"})

    {:ok, lv, html} = live(conn, ~p"/plays")

    assert has_element?(lv, "a[href='/plays/#{original.code}']", original.title)
    assert has_element?(lv, "a[href='/plays/#{translation.code}']", translation.title)
    refute html =~ draft.title
    # The translation is listed once, under its original, not as a play of its own.
    assert length(Regex.scan(~r{href="/plays/#{translation.code}"}, html)) == 1
  end

  test "searching narrows the list and keeps the search in the address", %{conn: conn} do
    complete(%{"title" => "La vida es sueño", "author_name" => "Calderón"})
    complete(%{"title" => "Fuenteovejuna", "author_name" => "Lope de Vega"})

    {:ok, lv, _html} = live(conn, ~p"/plays")

    html = lv |> element("#catalogue-search") |> render_change(%{"search" => "Lope"})

    assert_patch(lv, ~p"/plays?search=Lope")
    assert html =~ "Fuenteovejuna"
    refute html =~ "La vida es sueño"
  end

  test "25 plays to a page", %{conn: conn} do
    for n <- 1..26,
        do:
          complete(%{
            "title" => "Obra #{String.pad_leading("#{n}", 2, "0")}",
            "title_sort" => "Obra #{String.pad_leading("#{n}", 2, "0")}"
          })

    {:ok, lv, html} = live(conn, ~p"/plays")
    assert html =~ "Obra 25"
    refute html =~ "Obra 26"

    html = lv |> element("a[href='/plays?page=2']") |> render_click()
    assert html =~ "Obra 26"
    refute html =~ "Obra 01"
  end

  # This test used to pin the opposite: a draft was left out of the list but served to
  # anyone who had its code. A draft is now for staff only, here and through
  # /plays/:code/compare, /export/:id and /api/v1. Staff keep it because the admin
  # pages link here as a preview, and a freshly imported play is a draft.
  test "a draft is not listed, and its page is for staff only", %{conn: conn} do
    draft = play_fixture(%{"title" => "Borrador sin terminar"})

    {:ok, _lv, list} = live(conn, ~p"/plays")
    refute list =~ draft.title

    assert_error_sent 404, fn -> get(conn, ~p"/plays/#{draft.code}") end

    {:ok, _lv, page} = conn |> log_in_user(user_fixture()) |> live(~p"/plays/#{draft.code}")
    assert page =~ draft.title
  end
end
