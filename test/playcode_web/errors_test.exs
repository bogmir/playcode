defmodule PlaycodeWeb.ErrorsTest do
  use PlaycodeWeb.ConnCase, async: true

  test "a play that does not exist is a plain 404 page", %{conn: conn} do
    conn = log_in_user(conn, Playcode.TestFixtures.user_fixture())
    {status, _headers, body} = assert_error_sent 404, fn -> get(conn, ~p"/plays/NOPE0000") end

    assert status == 404
    assert body == "Not Found"
  end

  test "a JSON client asking for a route that does not exist gets a JSON 404", %{conn: conn} do
    conn = conn |> put_req_header("accept", "application/json") |> get("/nope")

    assert json_response(conn, 404) == %{"errors" => %{"detail" => "Not Found"}}
  end

  test "there is no self-registration page", %{conn: conn} do
    assert get(conn, "/users/register").status == 404
  end
end
