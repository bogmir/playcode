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
