defmodule PlaycodeWeb.FlyClientIpTest do
  # Not async: it switches :behind_fly, which every login test reads.
  use PlaycodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Playcode.TestFixtures

  setup do
    behind_fly = Application.get_env(:playcode, :behind_fly)
    Application.put_env(:playcode, :behind_fly, false)
    on_exit(fn -> Application.put_env(:playcode, :behind_fly, behind_fly) end)
  end

  test "off Fly, a client's own Fly-Client-IP is ignored", %{conn: conn} do
    conn =
      %{conn | remote_ip: {10, 8, 0, 1}}
      |> put_req_header("fly-client-ip", "203.0.113.9")
      |> post(~p"/users/log-in",
        user: %{"email" => user_fixture().email, "password" => valid_user_password()}
      )

    {:ok, lv, _html} = conn |> recycle() |> live(~p"/users/settings")
    sessions = lv |> element("[role=region][aria-label='#{t("Active sessions")}']") |> render()

    assert sessions =~ "10.8.0.1"
    refute sessions =~ "203.0.113.9"
  end
end
