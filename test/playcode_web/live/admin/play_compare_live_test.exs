defmodule PlaycodeWeb.Admin.PlayCompareLiveTest do
  @moduledoc """
  The admin comparison at /admin/plays/:id/compare: the side-by-side reading view, and the
  pair review a translation's speeches get against its original's.
  """
  use PlaycodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playcode.TestFixtures
  import Playcode.ImportHelpers

  setup %{conn: conn} do
    Map.put(split_speech_editions(), :conn, log_in_user(conn, user_fixture(role: :researcher)))
  end

  test "offers no HTML download: the site publishes the comparison", %{conn: conn, french: french} do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{french.id}/compare")

    refute has_element?(lv, "a[href^='/admin/plays/compare/export']")
    # The old link now reads "compare" as a play's id: a bad request, not a download.
    assert_error_sent 400, fn ->
      get(conn, "/admin/plays/compare/export/html?plays=#{french.id}")
    end
  end
end

defmodule PlaycodeWeb.Admin.PlayComparePairsTest do
  @moduledoc "The admin comparison's pair review (problem 5, step 5)."
  use PlaycodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playcode.TestFixtures
  import Playcode.ImportHelpers

  alias Playcode.Catalogue

  setup %{conn: conn} do
    Map.put(split_speech_editions(), :conn, log_in_user(conn, user_fixture(role: :researcher)))
  end

  defp text(lv, selector),
    do:
      lv
      |> element(selector)
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.text()
      |> String.split()
      |> Enum.join(" ")

  defp rows(lv) do
    lv
    |> render()
    |> LazyHTML.from_document()
    |> LazyHTML.query("[id^='pair-row-']")
    |> Enum.map(&(&1 |> LazyHTML.text() |> String.split() |> Enum.join(" ")))
  end

  test "two tabs, the side-by-side view first", %{conn: conn, french: french} do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{french.id}/compare")

    assert has_element?(lv, "a[aria-current='page']", t("Side by side"))
    lv |> element("a", t("Pair review")) |> render_click()
    assert_patch(lv, ~p"/admin/plays/#{french.id}/compare?view=pairs")
    assert has_element?(lv, "a[aria-current='page']", t("Pair review"))
  end

  test "one row per speech in the original's order, with the kind of pairing",
       %{conn: conn, french: french} do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{french.id}/compare?view=pairs")

    kinds = Enum.map(rows(lv), fn row -> Enum.find(~w(same split), &(row =~ t(label(&1)))) end)
    assert kinds == ~w(same same split same)
    assert rows(lv) |> hd() =~ "ANTONY"
    assert rows(lv) |> hd() =~ "ANTOINE"
    assert text(lv, "#pair-count-same") == "#{t("Same speaker")}: 3"
    assert text(lv, "#pair-count-split") == "#{t("Split")}: 1"
  end

  defp label("same"), do: "Same speaker"
  defp label("split"), do: "Split"

  test "opened on the original, it reviews its translation",
       %{conn: conn, original: original, french: french} do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{original.id}/compare?view=pairs")

    assert has_element?(lv, "select[name='translation'] option[selected][value='#{french.id}']")
    assert length(rows(lv)) == 4
  end

  test "a translation from the URL that is not the family's falls back to the default",
       %{conn: conn, french: french} do
    stranger = play_fixture(%{"title" => "Otra obra"})

    for id <- [stranger.id, "garbage"] do
      {:ok, lv, _html} =
        live(conn, ~p"/admin/plays/#{french.id}/compare?#{[view: "pairs", translation: id]}")

      assert length(rows(lv)) == 4
    end
  end

  test "a family with no translation or version has nothing to review", %{conn: conn} do
    %{original: original} = split_speech_editions("adaptacion")
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{original.id}/compare?view=pairs")

    assert rows(lv) == []
    assert render(lv) =~ t("No translation or version of this play to review.")
  end

  test "acts the translation does not share still list in the original's order",
       %{conn: conn} do
    original =
      import_tei!(
        tei(
          front: """
          <div type="elenco"><castList>
            <castItem><role xml:id="ANT">ANTONY</role></castItem>
            <castItem><role xml:id="CLEO">CLEOPATRA</role></castItem>
          </castList></div>
          """,
          body: """
          <div1 type="act" n="1"><head>ACT I</head>
            <sp who="#ANT"><speaker>ANTONY</speaker><l n="1">One.</l></sp>
            <sp who="#CLEO"><speaker>CLEOPATRA</speaker><l n="2">Two.</l></sp>
          </div1>
          <div1 type="act" n="2"><head>ACT II</head>
            <sp who="#ANT"><speaker>ANTONY</speaker><l n="3">Three.</l></sp>
          </div1>
          """
        )
      )

    french =
      import_tei!(
        tei(
          front: """
          <div type="elenco"><castList>
            <castItem><role xml:id="antoine">ANTOINE</role></castItem>
            <castItem><role xml:id="cleopatre">CLÉOPÂTRE</role></castItem>
          </castList></div>
          """,
          body: """
          <div1 type="act" n="1"><head>ACTE UNIQUE</head>
            <sp who="#antoine"><speaker>ANTOINE</speaker><p>Un.</p></sp>
            <sp who="#cleopatre"><speaker>CLÉOPÂTRE</speaker><p>Deux.</p></sp>
            <sp who="#antoine"><speaker>ANTOINE</speaker><p>Trois.</p></sp>
          </div1>
          """
        )
      )

    {:ok, french} =
      Catalogue.update_play(french, %{
        parent_play_id: original.id,
        relationship_type: "traduccion"
      })

    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{french.id}/compare?view=pairs")

    assert Enum.map(rows(lv), &Regex.run(~r/One|Two|Three/, &1)) == [["One"], ["Two"], ["Three"]]
  end
end
