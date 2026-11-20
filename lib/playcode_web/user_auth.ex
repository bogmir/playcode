defmodule PlaycodeWeb.UserAuth do
  @moduledoc """
  Handles user authentication for both regular HTTP requests and LiveView.
  """
  use PlaycodeWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  use Gettext, backend: PlaycodeWeb.Gettext

  alias Playcode.Accounts
  alias Playcode.Authz

  # Keep in step with @session_validity_in_days in UserToken.
  @max_age 60 * 60 * 24 * 30
  @remember_me_cookie "_playcode_web_user_remember_me"
  @remember_me_options [sign: true, max_age: @max_age, same_site: "Lax"]

  @doc """
  Logs the user in.

  It renews the session ID and clears the whole session
  to avoid fixation attacks. See the renew_session
  function to customize this behaviour.

  It also sets a `:live_socket_id` key in the session,
  so LiveView sessions are identified and automatically
  disconnected on log out.
  """
  def log_in_user(conn, user, params \\ %{}) do
    token = Accounts.generate_user_session_token(user, device_info(conn))
    user_return_to = get_session(conn, :user_return_to)

    conn
    |> renew_session()
    |> put_token_in_session(token)
    |> maybe_write_remember_me_cookie(token, params)
    |> redirect(to: user_return_to || signed_in_path(conn, user))
  end

  defp device_info(conn) do
    %{
      ip_address: conn.remote_ip |> :inet.ntoa() |> to_string(),
      user_agent: conn |> get_req_header("user-agent") |> List.first()
    }
  end

  defp maybe_write_remember_me_cookie(conn, token, %{"remember_me" => "true"}) do
    put_resp_cookie(conn, @remember_me_cookie, token, @remember_me_options)
  end

  defp maybe_write_remember_me_cookie(conn, _token, _params) do
    conn
  end

  # Renews the session ID and erases the whole session to avoid fixation attacks.
  defp renew_session(conn) do
    preferred_locale = get_session(conn, :locale)
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
    |> put_session(:locale, preferred_locale)
  end

  @doc """
  Logs the user out.

  It clears all session data for safety. See renew_session.
  """
  def log_out_user(conn) do
    user_token = get_session(conn, :user_token)
    user_token && Accounts.delete_user_session_token(user_token)

    if live_socket_id = get_session(conn, :live_socket_id) do
      PlaycodeWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session()
    |> delete_resp_cookie(@remember_me_cookie)
    |> redirect(to: ~p"/")
  end

  @doc """
  Authenticates the user by looking into the session
  and remember me token.
  """
  def fetch_current_user(conn, _opts) do
    {user_token, conn} = ensure_user_token(conn)
    user = user_token && Accounts.get_user_by_session_token(user_token)
    assign(conn, :current_user, user)
  end

  defp ensure_user_token(conn) do
    if token = get_session(conn, :user_token) do
      {token, conn}
    else
      conn = fetch_cookies(conn, signed: [@remember_me_cookie])

      if token = conn.cookies[@remember_me_cookie] do
        {token, put_token_in_session(conn, token)}
      else
        {nil, conn}
      end
    end
  end

  @doc """
  Handles mounting and authenticating the current_user in LiveViews.

  ## `on_mount` arguments

    * `:mount_current_user` - Assigns current_user
      to socket assigns based on user_token, or nil if
      there's no user_token or no matching user.

    * `:ensure_authenticated` - Authenticates the user from the session,
      and assigns the current_user to socket assigns based
      on user_token.
      Redirects to login page if there's no logged user.

    * `{:ensure_can, action}` - Same as `:ensure_authenticated` but also
      checks `Playcode.Authz.can?/3` for `action`.

    * `:redirect_if_user_is_authenticated` - Authenticates the user from the session.
      Redirects to signed_in_path if there's a logged user.

  ## Examples

  Use the `on_mount` lifecycle macro in LiveViews to mount or authenticate
  the current_user:

      defmodule PlaycodeWeb.PageLive do
        use PlaycodeWeb, :live_view

        on_mount {PlaycodeWeb.UserAuth, :mount_current_user}
        ...
      end

  Or use the `live_session` of your router to invoke the on_mount callback:

      live_session :authenticated, on_mount: [{PlaycodeWeb.UserAuth, :ensure_authenticated}] do
        live "/profile", ProfileLive, :index
      end
  """
  def on_mount(:mount_current_user, _params, session, socket) do
    {:cont, mount_current_user(socket, session)}
  end

  def on_mount(:ensure_authenticated, _params, session, socket) do
    socket = mount_current_user(socket, session)

    if Accounts.active?(socket.assigns.current_user) do
      {:cont, socket}
    else
      {:halt, redirect_to_login(socket)}
    end
  end

  def on_mount({:ensure_can, action}, _params, session, socket) do
    socket = mount_current_user(socket, session)
    user = socket.assigns.current_user

    cond do
      not Accounts.active?(user) ->
        {:halt, redirect_to_login(socket)}

      Authz.can?(user, action) ->
        {:cont, socket}

      true ->
        socket =
          socket
          |> Phoenix.LiveView.put_flash(:error, gettext("You do not have access to that page."))
          |> Phoenix.LiveView.redirect(to: ~p"/")

        {:halt, socket}
    end
  end

  def on_mount(:redirect_if_user_is_authenticated, _params, session, socket) do
    socket = mount_current_user(socket, session)

    if socket.assigns.current_user do
      {:halt, Phoenix.LiveView.redirect(socket, to: signed_in_path(socket))}
    else
      {:cont, socket}
    end
  end

  defp redirect_to_login(socket) do
    socket
    |> Phoenix.LiveView.put_flash(:error, gettext("You must log in to access this page."))
    |> Phoenix.LiveView.redirect(to: ~p"/users/log-in")
  end

  defp mount_current_user(socket, session) do
    Phoenix.Component.assign_new(socket, :current_user, fn ->
      if user_token = session["user_token"] do
        Accounts.get_user_by_session_token(user_token)
      end
    end)
  end

  @doc """
  Used for routes that require the user to not be authenticated.
  """
  def redirect_if_user_is_authenticated(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
      |> redirect(to: signed_in_path(conn))
      |> halt()
    else
      conn
    end
  end

  @doc """
  Used for routes that require an active user: authenticated, confirmed
  and not deactivated.
  """
  def require_authenticated_user(conn, _opts) do
    user = conn.assigns[:current_user]

    cond do
      is_nil(user) ->
        conn
        |> put_flash(:error, gettext("You must log in to access this page."))
        |> maybe_store_return_to()
        |> redirect(to: ~p"/users/log-in")
        |> halt()

      not Accounts.active?(user) ->
        reject_inactive(conn)

      true ->
        conn
    end
  end

  # Destroys the session of a user whose account is no longer usable, so they
  # get an explanation instead of a redirect loop.
  defp reject_inactive(conn) do
    user_token = get_session(conn, :user_token)
    user_token && Accounts.delete_user_session_token(user_token)

    conn
    |> renew_session()
    |> delete_resp_cookie(@remember_me_cookie)
    |> put_flash(
      :error,
      gettext("Your account is not active. Please contact an administrator.")
    )
    |> redirect(to: ~p"/users/log-in")
    |> halt()
  end

  @doc """
  Plug requiring a named permission. Takes the action as its option:

      plug :require_permission, :view_admin
  """
  def require_permission(conn, action) do
    user = conn.assigns[:current_user]

    cond do
      is_nil(user) or not Accounts.active?(user) ->
        require_authenticated_user(conn, [])

      Authz.can?(user, action) ->
        conn

      true ->
        conn
        |> put_flash(:error, gettext("You do not have access to that page."))
        |> redirect(to: ~p"/")
        |> halt()
    end
  end

  defp put_token_in_session(conn, token) do
    conn
    |> put_session(:user_token, token)
    |> put_session(:live_socket_id, "users_sessions:#{Base.url_encode64(token)}")
  end

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :user_return_to, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn

  defp signed_in_path(conn_or_socket, user \\ nil) do
    current_user =
      user ||
        conn_or_socket
        |> Map.get(:assigns, %{})
        |> Map.get(:current_user)

    if Authz.can?(current_user, :view_admin), do: ~p"/admin/plays", else: ~p"/"
  end
end
