defmodule Playcode.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Playcode.Repo
  alias Playcode.Accounts.{User, UserToken}

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  ## Invitations

  @doc """
  Creates or re-invites a user.

  Returns `{:ok, user, raw_token}`. Any outstanding invite token for the user
  is deleted first, so re-inviting invalidates the earlier link. Refuses to
  invite an account that can already log in.
  """
  def invite_user(email, role, invited_by \\ nil) when is_binary(email) do
    case get_user_by_email(email) do
      %User{} = user ->
        if active?(user), do: {:error, :already_active}, else: issue_invite(user, role)

      nil ->
        %User{}
        |> User.invite_changeset(%{email: email, role: role})
        |> Repo.insert()
        |> case do
          {:ok, user} -> issue_invite(user, role)
          {:error, changeset} -> {:error, changeset}
        end
    end
    |> tap(fn
      {:ok, user, _token} -> log_invite(user, invited_by)
      _ -> :ok
    end)
  end

  defp issue_invite(user, role) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "invite")

    Ecto.Multi.new()
    |> Ecto.Multi.delete_all(:old, UserToken.by_user_and_contexts_query(user, ["invite"]))
    |> Ecto.Multi.update(:user, User.role_changeset(user, %{role: role}))
    |> Ecto.Multi.insert(:token, user_token)
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user, encoded_token}
      {:error, _, changeset, _} -> {:error, changeset}
    end
  end

  defp log_invite(_user, nil), do: :ok

  defp log_invite(user, %User{} = invited_by) do
    Playcode.ActivityLog.log(%{
      user_id: invited_by.id,
      action: "invite",
      resource_type: "user",
      resource_id: user.id,
      metadata: %{"email" => user.email, "role" => to_string(user.role)}
    })

    :ok
  end

  @doc """
  Mails the invitation link.
  """
  def deliver_invite(%User{} = user, token, url_fun) when is_function(url_fun, 1) do
    Playcode.Accounts.UserNotifier.deliver_invite_instructions(user, url_fun.(token))
  end

  @doc """
  Returns the user for a valid, unexpired invite token, or nil.
  """
  def get_user_by_invite_token(token) when is_binary(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "invite"),
         %User{} = user <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Changeset for the accept-invitation form.
  """
  def change_user_invite_acceptance(%User{} = user, attrs \\ %{}) do
    User.accept_invite_changeset(user, attrs, hash_password: false)
  end

  @doc """
  Sets the password, confirms the account and consumes the invite token.
  """
  def accept_invite(%User{} = user, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.accept_invite_changeset(user, attrs))
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, ["invite"]))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  ## Settings

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}) do
    User.password_changeset(user, attrs, hash_password: false)
  end

  @doc """
  Updates the user password.

  ## Examples

      iex> update_user_password(user, "valid password", %{password: ...})
      {:ok, %User{}}

      iex> update_user_password(user, "invalid password", %{password: ...})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, password, attrs) do
    changeset =
      user
      |> User.password_changeset(attrs)
      |> User.validate_current_password(password)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  ## Session

  @doc """
  Generates a session token, optionally recording the issuing device.
  """
  def generate_user_session_token(user, device_info \\ %{}) do
    {token, user_token} = UserToken.build_session_token(user, device_info)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Lists the user's session tokens, newest first.
  """
  def list_user_sessions(%User{} = user) do
    from(t in UserToken,
      where: t.user_id == ^user.id and t.context == "session",
      order_by: [desc: t.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Deletes one of the user's own sessions by token id.

  Scoped by `user_id`: the id arrives from the browser, so an unscoped query
  would let one user end another's session.
  """
  def delete_user_session(%User{} = user, token_id) do
    from(t in UserToken,
      where: t.user_id == ^user.id and t.context == "session" and t.id == ^token_id
    )
    |> Repo.all()
    |> disconnect_and_delete()
  end

  @doc """
  Deletes every session except the one identified by `current_token`.
  """
  def delete_other_user_sessions(%User{} = user, current_token) do
    from(t in UserToken,
      where: t.user_id == ^user.id and t.context == "session" and t.token != ^current_token
    )
    |> Repo.all()
    |> disconnect_and_delete()
  end

  @doc """
  Deletes every session the user holds. Used by admins to evict someone.
  """
  def force_logout(%User{} = user) do
    from(t in UserToken, where: t.user_id == ^user.id and t.context == "session")
    |> Repo.all()
    |> disconnect_and_delete()
  end

  # The topic must match the live_socket_id written in put_token_in_session/2,
  # so open LiveViews drop at once instead of on their next navigation.
  defp disconnect_and_delete(tokens) do
    Enum.each(tokens, fn token ->
      PlaycodeWeb.Endpoint.broadcast(
        "users_sessions:#{Base.url_encode64(token.token)}",
        "disconnect",
        %{}
      )

      Repo.delete!(token)
    end)

    :ok
  end

  @doc """
  Gets the user with the given signed token.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(UserToken.by_token_and_context_query(token, "session"))
    :ok
  end

  ## Reset password

  @doc ~S"""
  Delivers the reset password email instructions to the given user.

  ## Examples

      iex> deliver_user_reset_password_instructions(user, &url(~p"/users/reset-password/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_reset_password_instructions(%User{} = user, reset_password_url_fun)
      when is_function(reset_password_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "reset_password")
    Repo.insert!(user_token)

    Playcode.Accounts.UserNotifier.deliver_reset_password_instructions(
      user,
      reset_password_url_fun.(encoded_token)
    )
  end

  @doc """
  Gets the user by reset password token.

  ## Examples

      iex> get_user_by_reset_password_token("validtoken")
      %User{}

      iex> get_user_by_reset_password_token("invalidtoken")
      nil

  """
  def get_user_by_reset_password_token(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "reset_password"),
         %User{} = user <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Resets the user password.

  ## Examples

      iex> reset_user_password(user, %{password: "new long password", password_confirmation: "new long password"})
      {:ok, %User{}}

  """
  def reset_user_password(user, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.reset_password_changeset(user, attrs))
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  ## Role management

  @doc """
  True when this user's email is listed in `ADMIN_EMAILS`.

  Protected admins cannot be demoted, deactivated or deleted from the UI.
  Enforce this here, not by hiding a button.
  """
  def protected_admin?(%User{email: email}) do
    String.downcase(email) in Playcode.Accounts.AdminBootstrap.configured_emails()
  end

  def protected_admin?(_), do: false

  @doc """
  Returns true if the user has confirmed their email address.
  """
  def confirmed?(%User{confirmed_at: confirmed_at}), do: not is_nil(confirmed_at)
  def confirmed?(_), do: false

  @doc """
  Returns true if the user may log in: confirmed and not deactivated.
  """
  def active?(%User{confirmed_at: confirmed_at, deactivated_at: nil})
      when not is_nil(confirmed_at),
      do: true

  def active?(_), do: false

  @doc """
  Deactivates a user and destroys every token they hold.

  Deactivation rather than deletion, because `activity_logs.user_id`
  references this row.
  """
  def deactivate_user(%User{} = user) do
    tokens = Repo.all(UserToken.by_user_and_contexts_query(user, :all))

    changeset = Ecto.Changeset.change(user, deactivated_at: DateTime.utc_now(:second))

    case Repo.update(changeset) do
      {:ok, user} ->
        disconnect_and_delete(tokens)
        {:ok, user}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Clears `deactivated_at`. Does not restore any tokens.
  """
  def reactivate_user(%User{} = user) do
    user |> Ecto.Changeset.change(deactivated_at: nil) |> Repo.update()
  end

  ## User listing (admin)

  @doc """
  Lists users with optional search and pagination.
  """
  def list_users(opts \\ []) do
    search = Keyword.get(opts, :search, "")
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 50)

    User
    |> search_users(search)
    |> order_by(:inserted_at)
    |> limit(^per_page)
    |> offset(^((page - 1) * per_page))
    |> Repo.all()
  end

  @doc """
  Counts users with optional search filter.
  """
  def count_users(opts \\ []) do
    User
    |> search_users(Keyword.get(opts, :search, ""))
    |> Repo.aggregate(:count)
  end

  defp search_users(query, ""), do: query

  defp search_users(query, search) do
    like = "%#{search}%"
    where(query, [u], ilike(u.email, ^like))
  end

  @doc """
  Updates the role of a user.
  """
  def update_user_role(%User{} = user, role) do
    changeset = User.role_changeset(user, %{role: role})

    changeset =
      if role in ["admin", :admin] and is_nil(user.confirmed_at),
        do: Ecto.Changeset.change(changeset, %{confirmed_at: DateTime.utc_now(:second)}),
        else: changeset

    Repo.update(changeset)
  end
end
