defmodule Playcode.Accounts.AdminBootstrap do
  @moduledoc """
  Reconciles the `ADMIN_EMAILS` configuration against the users table at boot.

  Config is the source of truth for who is an admin. Because these accounts
  cannot be demoted, deactivated or deleted through the UI, a compromised
  admin session cannot strip the co-admins or lock the owner out.

  Runs once at startup as a `Task`; a failure here must never stop the
  supervision tree, so every error is logged rather than raised.
  """

  require Logger

  alias Playcode.Accounts
  alias Playcode.Accounts.User

  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {Task, :start_link, [&run/0]},
      restart: :transient
    }
  end

  def run do
    case configured_emails() do
      [] ->
        if Application.get_env(:playcode, :env) == :prod do
          Logger.error("ADMIN_EMAILS is not set — nobody can administer this instance")
        end

        :ok

      emails ->
        reconcile(emails)
    end
  end

  @doc """
  Returns the configured admin addresses, downcased and trimmed.
  """
  def configured_emails do
    :playcode
    |> Application.get_env(:admin_emails, [])
    |> Enum.map(&(&1 |> to_string() |> String.trim() |> String.downcase()))
    |> Enum.reject(&(&1 == ""))
  end

  @doc """
  Ensures every address in `emails` exists as an active-or-invited admin.
  """
  def reconcile(emails) when is_list(emails) do
    Enum.each(emails, &reconcile_one/1)
  end

  defp reconcile_one(email) do
    case Accounts.get_user_by_email(email) do
      nil -> invite_admin(email)
      %User{} = user -> repair_admin(user)
    end
  rescue
    error ->
      Logger.error("admin bootstrap failed for #{email}: #{Exception.message(error)}")
      :ok
  end

  defp invite_admin(email) do
    case Accounts.invite_user(email, :admin, nil) do
      {:ok, user, token} ->
        case Accounts.deliver_invite(user, token, &invite_url/1) do
          {:ok, _email} ->
            Logger.info("admin bootstrap: invited #{email}")

          {:error, _reason} ->
            # The notifier already logged why. Say what it means for the
            # operator: the account exists but nobody received a link, so
            # break-glass is the way in.
            Logger.error(
              "admin bootstrap: #{email} was invited but the mail was not delivered — " <>
                "use Playcode.Release.invite_url(\"#{email}\") to get the link"
            )
        end

      {:error, reason} ->
        Logger.error("admin bootstrap: could not invite #{email}: #{inspect(reason)}")
    end

    :ok
  end

  defp repair_admin(user) do
    if user.role != :admin do
      {:ok, _} = Accounts.update_user_role(user, :admin)
      Logger.info("admin bootstrap: promoted #{user.email}")
    end

    if Accounts.status(user) == :deactivated do
      {:ok, _} = Accounts.reactivate_user(user)
      Logger.info("admin bootstrap: reactivated #{user.email}")
    end

    :ok
  end

  @doc """
  Builds the accept-invite URL for a raw token.
  """
  def invite_url(token) do
    PlaycodeWeb.Endpoint.url() <> "/users/accept-invite/" <> token
  end
end
