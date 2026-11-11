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

defmodule PlaycodeWeb.Admin.PlayCompareDoubtfulTest do
  @moduledoc "The pair review's doubtful rows and its links to the Elenco."
  use PlaycodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playcode.TestFixtures
  import Playcode.ImportHelpers

  alias Playcode.{Catalogue, PlayContent}

  setup %{conn: conn}, do: %{conn: log_in_user(conn, user_fixture(role: :researcher))}

  # An original and its French translation, from their speeches' TEI.
  defp editions(original_sps, french_sps) do
    play = fn cast, sps ->
      import_tei!(
        tei(
          front: ~s(<div type="elenco"><castList>#{cast}</castList></div>),
          body: ~s(<div1 type="act" n="1"><head>I</head>#{sps}</div1>)
        )
      )
    end

    original =
      play.(
        ~s(<castItem><role xml:id="ANT">ANTONY</role></castItem><castItem><role xml:id="CLEO">CLEOPATRA</role></castItem>),
        original_sps
      )

    french =
      play.(
        ~s(<castItem><role xml:id="antoine">ANTOINE</role></castItem><castItem><role xml:id="cleopatre">CLÉOPÂTRE</role></castItem>),
        french_sps
      )

    {:ok, french} =
      Catalogue.update_play(french, %{
        parent_play_id: original.id,
        relationship_type: "traduccion"
      })

    french
  end

  defp sp(who, words), do: ~s(<sp who="##{who}"><speaker>#{who}</speaker><p>#{words}</p></sp>)

  defp rows(lv) do
    lv
    |> render()
    |> LazyHTML.from_document()
    |> LazyHTML.query("[id^='pair-row-']")
    |> Enum.map(&(&1 |> LazyHTML.attribute("id") |> hd()))
  end

  defp review(conn, french) do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{french.id}/compare?view=pairs")
    lv
  end

  test "a same-speaker pair of very different length is doubtful, two short ones are not",
       %{conn: conn} do
    long = String.duplicate("word ", 40)

    french =
      editions(
        sp("ANT", long) <> sp("CLEO", "Yes."),
        sp("antoine", "Oui.") <> sp("cleopatre", "Oui, oui, monseigneur, très volontiers.")
      )

    lv = review(conn, french)

    assert lv |> element("#pair-row-1") |> render() =~ t("Very different length")
    refute lv |> element("#pair-row-2") |> render() =~ t("Very different length")
  end

  test "only the doubtful rows, with one row either side", %{conn: conn} do
    original =
      Enum.map_join(1..6, &sp(if(rem(&1, 2) == 1, do: "ANT", else: "CLEO"), "Line #{&1}."))

    french =
      Enum.map_join(
        1..5,
        &sp(if(rem(&1, 2) == 1, do: "antoine", else: "cleopatre"), "Ligne #{&1}.")
      ) <>
        ~s(<stage>Il sort.</stage>) <>
        sp("antoine", "Encore.") <> sp("cleopatre", "Six.")

    lv = review(conn, editions(original, french))
    assert length(rows(lv)) == 7

    lv |> element("input[name='doubtful']") |> render_click()

    # Row 6 is the split; rows 5 and 7 stand beside it.
    assert rows(lv) == ~w(pair-row-5 pair-row-6 pair-row-7)
  end

  test "a row repeating the original speech above it says so, not prints it again",
       %{conn: conn} do
    french =
      editions(
        sp("ANT", "One.") <> sp("CLEO", "Two."),
        sp("antoine", "Un.") <> sp("nadie", "Ajouté.") <> sp("cleopatre", "Deux.")
      )

    lv = review(conn, french)
    added = lv |> element("#pair-row-2") |> render()

    assert added =~ t("Same speech as above")
    refute added =~ "One."
  end

  test "an archived original is not reviewed, as the side view does not show it",
       %{conn: conn} do
    french = editions(sp("ANT", "One."), sp("antoine", "Un."))
    {:ok, _} = french.parent_play_id |> Catalogue.get_play!() |> Catalogue.delete_play()

    lv = review(conn, french)

    assert rows(lv) == []
    assert render(lv) =~ t("No translation or version of this play to review.")
  end

  test "a speaker links to its line on the translation's Elenco, a speech naming no role does not",
       %{conn: conn} do
    french =
      editions(
        sp("ANT", "One.") <> sp("CLEO", "Two."),
        sp("antoine", "Un.") <> sp("nadie", "Deux.")
      )

    entry = french.id |> PlayContent.list_cast_lists() |> hd() |> Map.get(:entries) |> hd()
    lv = review(conn, french)

    assert has_element?(
             lv,
             "#pair-row-1 a[href='/admin/plays/#{french.id}/content#entry-#{entry.id}']",
             "antoine"
           )

    refute has_element?(lv, "#pair-row-2 a")
  end
end
