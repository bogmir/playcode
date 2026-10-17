defmodule PlaycodeWeb.PlayCompareLiveTest do
  use PlaycodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playcode.ImportHelpers

  alias Playcode.TestFixtures

  describe "catalogue compare icon" do
    test "shows the compare icon only for plays with linked plays", %{conn: conn} do
      %{original: original} = TestFixtures.translation_family_fixture()
      standalone = TestFixtures.play_fixture(%{"title" => "Lonely Play"})

      {:ok, view, _html} = live(conn, ~p"/plays")

      assert has_element?(view, "a[href='/plays/#{original.code}/compare']")
      refute has_element?(view, "a[href='/plays/#{standalone.code}/compare']")
    end
  end

  describe "public comparison page" do
    test "requires no authentication and renders the family panels", %{conn: conn} do
      %{original: original, translation: translation} = TestFixtures.translation_family_fixture()

      {:ok, _view, html} = live(conn, ~p"/plays/#{original.code}/compare")

      # First panel is the play itself; the linked translation is offered to add.
      assert html =~ original.title
      assert html =~ translation.title
    end

    test "auto-includes the parent panel when viewing a translation", %{conn: conn} do
      %{original: original, translation: translation} = TestFixtures.translation_family_fixture()

      {:ok, view, _html} = live(conn, ~p"/plays/#{translation.code}/compare")

      # Two panels: parent (original) prepended, then the translation.
      assert view |> element("[data-panel='panel-0']") |> has_element?()
      assert view |> element("[data-panel='panel-1']") |> has_element?()
      assert render(view) =~ original.title
    end

    # Question 15 made The Shy Courtier an adaptation; it must still open beside its original.
    test "auto-includes the parent panel when viewing an adaptation", %{conn: conn} do
      original = TestFixtures.play_fixture(%{"title" => "El vergonzoso", "is_complete" => true})

      adaptation =
        TestFixtures.play_fixture(%{
          "parent_play_id" => original.id,
          "relationship_type" => "adaptacion",
          "is_complete" => true
        })

      {:ok, view, _html} = live(conn, ~p"/plays/#{adaptation.code}/compare")

      assert view |> element("[data-panel='panel-1']") |> has_element?()
      assert render(view) =~ "El vergonzoso"
    end

    test "add_play and remove_panel manage panels", %{conn: conn} do
      %{original: original, translation: translation} = TestFixtures.translation_family_fixture()

      {:ok, view, _html} = live(conn, ~p"/plays/#{original.code}/compare")

      refute has_element?(view, "[data-panel='panel-1']")

      view
      |> element("form[phx-change='add_play']")
      |> render_change(%{"id" => translation.id})

      assert has_element?(view, "[data-panel='panel-1']")

      view
      |> element("button[phx-click='remove_panel'][phx-value-index='1']")
      |> render_click()

      refute has_element?(view, "[data-panel='panel-1']")
    end

    test "toggling display options updates the checkboxes", %{conn: conn} do
      %{original: original} = TestFixtures.translation_family_fixture()

      {:ok, view, _html} = live(conn, ~p"/plays/#{original.code}/compare")

      assert has_element?(view, "input[phx-click='toggle_line_numbers'][checked]")

      view
      |> element("input[phx-click='toggle_line_numbers']")
      |> render_click()

      refute has_element?(view, "input[phx-click='toggle_line_numbers'][checked]")
    end
  end

  describe "variants" do
    # Each panel follows its own play's Show variant readings.
    test "a panel shows its play's variants unless that play has them off", %{conn: conn} do
      body =
        ~s(<div1 type="acto" n="1"><sp><speaker>A</speaker><l n="1">uno<app n="1"><rdg wit="#B">dos</rdg></app> tres</l></sp></div1>)

      original = [body: body] |> tei() |> import_tei!() |> TestFixtures.mark_complete!()
      translation = [body: body] |> tei() |> import_tei!() |> TestFixtures.mark_complete!()

      {:ok, _} =
        Playcode.Catalogue.update_play(translation, %{
          parent_play_id: original.id,
          relationship_type: "traduccion",
          show_variants: false
        })

      # The translation's page opens with the original in the first panel.
      {:ok, view, _html} = live(conn, ~p"/plays/#{translation.code}/compare")
      variant = ~s(button[aria-label^="#{t("Textual variant")}"])

      assert has_element?(view, "[data-panel='panel-0'] #{variant}")
      refute has_element?(view, "[data-panel='panel-1'] #{variant}")
    end
  end

  describe "Hamlet's Folio passages" do
    # The comparison has no switch: a panel hides the passages, as the play page does by
    # default. The hiding is the stylesheet's, so the observable stand-in is the panel's
    # data-folio and the class its words carry.
    test "a panel shows them hidden, and offers no switch", %{conn: conn} do
      folio = ~s(<code>&lt;span class="folio"&gt;</code>)
      folio_end = ~s(<code>&lt;/span&gt;</code>)
      f = ~s(<code>&lt;sup&gt;</code>F<code>&lt;/sup&gt;</code>)

      body =
        ~s(<div1 type="acto" n="1"><sp><speaker>A</speaker><l n="1">uno #{folio}#{f}dos#{f}#{folio_end} tres</l></sp></div1>)

      original = [body: body] |> tei() |> import_tei!() |> TestFixtures.mark_complete!()
      translation = [body: body] |> tei() |> import_tei!() |> TestFixtures.mark_complete!()

      {:ok, _} =
        Playcode.Catalogue.update_play(translation, %{
          parent_play_id: original.id,
          relationship_type: "traduccion"
        })

      {:ok, view, _html} = live(conn, ~p"/plays/#{translation.code}/compare")

      assert has_element?(view, "[data-panel='panel-1'] [data-folio='off']")
      assert has_element?(view, "[data-panel='panel-1'] span.folio", "dos")
      refute has_element?(view, "[data-folio='on']")
      refute has_element?(view, "label", t("Folio interpolations"))
    end
  end

  describe "scroll sync and Hamlet's Folio passages" do
    # A speech the hidden passages leave without words has no box to scroll to: if it kept
    # data-sync-act, assets/js/sync_scroll.mjs would count it among the act's speeches and
    # could pick it as the counterpart of the other panel's speech.
    setup do
      folio = ~s(<code>&lt;span class="folio"&gt;</code>)
      folio_end = ~s(<code>&lt;/span&gt;</code>)
      f = ~s(<code>&lt;sup&gt;</code>F<code>&lt;/sup&gt;</code>)

      body = """
      <div1 type="acto" n="1"><head>ACT I</head>
        <sp><speaker>HAMLET</speaker><l n="1">uno</l></sp>
        <sp><speaker>#{folio}#{f}GUILDENSTERN#{folio_end}</speaker><p n="2">#{folio}Solo el Folio.#{f}#{folio_end}</p></sp>
        <sp><speaker>CLAUDIO</speaker><l n="3">tres</l></sp>
      </div1>
      """

      original = [body: body] |> tei() |> import_tei!() |> TestFixtures.mark_complete!()
      translation = [body: body] |> tei() |> import_tei!() |> TestFixtures.mark_complete!()

      {:ok, translation} =
        Playcode.Catalogue.update_play(translation, %{
          parent_play_id: original.id,
          relationship_type: "traduccion"
        })

      %{original: original, translation: translation}
    end

    test "a speech that is all the Folio's is not paired, and the others still are",
         %{conn: conn, translation: translation} do
      {:ok, view, _html} = live(conn, ~p"/plays/#{translation.code}/compare")
      page = view |> render() |> LazyHTML.from_fragment()

      for panel <- ["panel-0", "panel-1"] do
        speeches = LazyHTML.query(page, "[data-panel='#{panel}'] .speech")
        assert Enum.count(speeches) == 3
        assert LazyHTML.query(page, "[data-panel='#{panel}'] .speech.folio") |> Enum.count() == 1
        assert sync_keys(page, panel, "data-sync-act") == ["act-0", "act-0"]

        assert LazyHTML.query(page, "[data-panel='#{panel}'] .speech.folio[data-sync-act]")
               |> Enum.count() == 0
      end
    end

    test "it keeps its key while the passages are shown", %{translation: translation} do
      divisions = Playcode.PlayContent.load_play_content(translation.id)

      html =
        render_component(&PlaycodeWeb.Components.PlayText.play_body/1,
          divisions: divisions,
          sync_keys: true,
          show_folio: true
        )

      assert html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query(".speech[data-sync-act]")
             |> Enum.count() == 3
    end
  end

  describe "drafts" do
    test "a draft's comparison page is for staff only", %{conn: conn} do
      draft = TestFixtures.play_fixture(%{"title" => "Borrador comparado"})

      assert_error_sent 404, fn -> get(conn, ~p"/plays/#{draft.code}/compare") end

      staff = log_in_user(conn, TestFixtures.user_fixture())
      {:ok, _view, html} = live(staff, ~p"/plays/#{draft.code}/compare")
      assert html =~ draft.title
    end

    test "a draft relative is offered to staff only", %{conn: conn} do
      original =
        TestFixtures.play_fixture(%{"title" => "Original publicado", "is_complete" => true})

      draft =
        TestFixtures.play_fixture(%{
          "title" => "Traducción en curso",
          "parent_play_id" => original.id,
          "relationship_type" => "traduccion"
        })

      {:ok, _view, html} = live(conn, ~p"/plays/#{original.code}/compare")
      refute html =~ draft.title

      staff = log_in_user(conn, TestFixtures.user_fixture())
      {:ok, _view, html} = live(staff, ~p"/plays/#{original.code}/compare")
      assert html =~ draft.title
    end

    test "a play outside the offered family cannot be added as a panel", %{conn: conn} do
      original =
        TestFixtures.play_fixture(%{"title" => "Original publicado", "is_complete" => true})

      draft =
        TestFixtures.play_fixture(%{
          "title" => "Traducción en curso",
          "parent_play_id" => original.id,
          "relationship_type" => "traduccion"
        })

      {:ok, view, _html} = live(conn, ~p"/plays/#{original.code}/compare")

      # A hand-made event: the form never offers the draft to a visitor.
      html = render_change(view, "add_play", %{"id" => draft.id})

      refute has_element?(view, "[data-panel='panel-1']")
      refute html =~ draft.title
    end
  end

  describe "scroll sync" do
    # The data-sync-* attributes are the contract with assets/js/sync_scroll.mjs, which
    # pairs each speech with the one the same way through the same act in the other panel.
    test "speeches and headings are keyed by act, however each edition numbers its divisions",
         %{conn: conn} do
      %{original: original, translation: translation} = differently_numbered_editions()

      {:ok, view, _html} = live(conn, ~p"/plays/#{original.code}/compare")

      view
      |> element("form[phx-change='add_play']")
      |> render_change(%{"id" => translation.id})

      page = view |> render() |> LazyHTML.from_fragment()

      for panel <- ["panel-0", "panel-1"] do
        assert {panel, sync_keys(page, panel, "data-sync-div"),
                sync_keys(page, panel, "data-sync-act")} ==
                 {panel, ["act-0", "act-1", "act-1/scene-0"], ["act-0", "act-1", "act-1"]}
      end
    end
  end

  defp sync_keys(page, panel, attribute) do
    page
    |> LazyHTML.query("[data-panel='#{panel}'] [#{attribute}]")
    |> LazyHTML.attribute(attribute)
  end
end
