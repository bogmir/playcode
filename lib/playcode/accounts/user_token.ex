defmodule Playcode.Accounts.UserToken do
  @moduledoc """
  A token, by `context`: `"session"` (30 days, with the browser's IP and user agent, listed
  and revocable at /users/settings), `"invite"` (7 days) or `"reset_password"` (1 day). The
  mailed ones are stored as their SHA-256, so a database leak does not hand out working
  links; a session token is stored as it is.
  """

  use Ecto.Schema
  import Ecto.Query

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @hash_algorithm :sha256
  @rand_size 32

  # It is very important to keep the reset password token expiry short,
  # since someone with access to the email may take over the account.
  @reset_password_validity_in_days 1
  @invite_validity_in_days 7
  @session_validity_in_days 30

  schema "users_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string
    field :ip_address, :string
    field :user_agent, :string

    belongs_to :user, Playcode.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Builds a session token, recording where it was issued.

  Session tokens live in the database — not only in the signed cookie — so
  that individual sessions can be expired.

  `device_info` may carry `:ip_address` and `:user_agent`. They exist so the
  "active sessions" list is legible — a bare timestamp tells nobody which row
  is theirs. They are not identity: both change constantly and neither may
  ever be treated as an authentication factor.
  """
  def build_session_token(user, device_info \\ %{}) do
    token = :crypto.strong_rand_bytes(@rand_size)

    {token,
     %Playcode.Accounts.UserToken{
       token: token,
       context: "session",
       user_id: user.id,
       ip_address: Map.get(device_info, :ip_address),
       user_agent: device_info |> Map.get(:user_agent) |> truncate(255)
     }}
  end

  defp truncate(nil, _length), do: nil
  defp truncate(string, length), do: String.slice(string, 0, length)

  @doc """
  Checks if the token is valid and returns its underlying lookup query.

  The query returns the user found by the token, if any.

  The token is valid if it matches the value in the database and it has
  not expired (after @session_validity_in_days).
  """
  def verify_session_token_query(token) do
    query =
      from token in by_token_and_context_query(token, "session"),
        join: user in assoc(token, :user),
        where: token.inserted_at > ago(@session_validity_in_days, "day"),
        select: user

    {:ok, query}
  end

  @doc """
  Builds a token and its hash to be delivered to the user's email.

  The non-hashed token is sent to the user email while the
  hashed part is stored in the database. The original token cannot be
  reconstructed, which means anyone with read-only access to the
  database cannot directly use the token in the application to gain
  access. Furthermore, if the user changes their email in the system,
  the tokens sent to the previous email are no longer valid.

  Users can easily adapt the existing tokens to provide additional
  functionality, for example, to confirm phone numbers.
  """
  def build_email_token(user, context) do
    build_hashed_token(user, context, user.email)
  end

  defp build_hashed_token(user, context, sent_to) do
    token = :crypto.strong_rand_bytes(@rand_size)
    hashed_token = :crypto.hash(@hash_algorithm, token)

    {Base.url_encode64(token, padding: false),
     %Playcode.Accounts.UserToken{
       token: hashed_token,
       context: context,
       sent_to: sent_to,
       user_id: user.id
     }}
  end

  @doc """
  Checks if the token is valid and returns its underlying lookup query.

  The query returns the user found by the token, if any.

  The given token is valid if it matches its hashed counterpart in the
  database and the user email has not changed. This function also checks
  if the token is being used within a certain period, depending on the
  context. The default contexts supported by this function are either
  "confirm" or "reset_password".
  """
  def verify_email_token_query(token, context) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = :crypto.hash(@hash_algorithm, decoded_token)
        days = days_for_context(context)

        query =
          from token in by_token_and_context_query(hashed_token, context),
            join: user in assoc(token, :user),
            where: token.inserted_at > ago(^days, "day") and token.sent_to == user.email,
            select: user

        {:ok, query}

      :error ->
        :error
    end
  end

  defp days_for_context("reset_password"), do: @reset_password_validity_in_days
  defp days_for_context("invite"), do: @invite_validity_in_days

  @doc """
  Returns the token struct for the given token value and context.
  """
  def by_token_and_context_query(token, context) do
    from Playcode.Accounts.UserToken, where: [token: ^token, context: ^context]
  end

  @doc """
  Gets all tokens for the given user for the given contexts.
  """
  def by_user_and_contexts_query(user, :all) do
    from t in Playcode.Accounts.UserToken, where: t.user_id == ^user.id
  end

  def by_user_and_contexts_query(user, [_ | _] = contexts) do
    from t in Playcode.Accounts.UserToken,
      where: t.user_id == ^user.id and t.context in ^contexts
  end
end
