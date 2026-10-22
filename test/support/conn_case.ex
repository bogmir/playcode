defmodule PlaycodeWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use PlaycodeWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint PlaycodeWeb.Endpoint

      use PlaycodeWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import PlaycodeWeb.ConnCase
    end
  end

  setup tags do
    Playcode.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  The UI text for `msgid` in the test process's locale (the app default, "es").
  Assert on what the user reads, not on the English msgid.
  """
  def t(msgid, bindings \\ []), do: Gettext.gettext(PlaycodeWeb.Gettext, msgid, bindings)

  @doc "`t/2` for a plural entry, which `gettext/3` cannot reach."
  def n(singular, plural, count),
    do: Gettext.ngettext(PlaycodeWeb.Gettext, singular, plural, count)

  @doc """
  Puts a valid session token for `user` into `conn`.
  """
  def log_in_user(conn, user) do
    token = Playcode.Accounts.generate_user_session_token(user)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end
end
