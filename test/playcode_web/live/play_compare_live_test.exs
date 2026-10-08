defmodule PlaycodeWeb.PlayCompareLiveTest do
  use PlaycodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

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
end
