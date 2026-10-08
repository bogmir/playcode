defmodule Playcode.Accounts.User do
  @moduledoc """
  An account. There is no registration: `Accounts.invite_user/3` creates the row with no
  password, and accepting the invitation, or a password reset, sets `hashed_password` and
  `confirmed_at`. `role` is `:admin` or `:researcher`; what each may do is
  `Playcode.Authz`'s business. A deactivated account is kept, because the activity log
  points at it, but no gate lets it in.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :current_password, :string, virtual: true, redact: true
    field :role, Ecto.Enum, values: [:admin, :researcher], default: :researcher
    field :confirmed_at, :utc_datetime
    field :deactivated_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc """
  A changeset for creating an invited user: email and role, no password.
  """
  def invite_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :role])
    |> validate_required([:role])
    |> validate_email([])
  end

  @doc """
  A changeset for accepting an invitation: sets the password and marks the
  account confirmed, because clicking the emailed link proves control of the
  mailbox.
  """
  def accept_invite_changeset(user, attrs, opts \\ []) do
    user
    |> password_changeset(attrs, opts)
    |> put_change(:confirmed_at, DateTime.utc_now(:second))
  end

  @doc """
  A changeset for a password reset.

  Confirms the account if it was not confirmed yet, for the same reason
  accepting an invitation does: the reset link was mailed to that address, so
  following it proves control of the mailbox. Without this an invited user who
  reaches for "forgot password" instead of their invite link ends up with a
  working password on an account every gate refuses.

  Deliberately leaves `deactivated_at` alone — a reset must not resurrect an
  account an administrator switched off.
  """
  def reset_password_changeset(user, attrs, opts \\ []) do
    changeset = password_changeset(user, attrs, opts)

    if is_nil(user.confirmed_at) do
      put_change(changeset, :confirmed_at, DateTime.utc_now(:second))
    else
      changeset
    end
  end

  defp validate_email(changeset, opts) do
    changeset
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_length(:email, max: 160)
    |> maybe_validate_unique_email(opts)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 72)
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password && password && changeset.valid? do
      changeset
      # If using Bcrypt, then further duplicating the password
      # having Bcrypt.hash_pwd_salt/2 return a hash with the
      # same salt is not possible.
      |> validate_length(:password, max: 72, count: :bytes)
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  defp maybe_validate_unique_email(changeset, opts) do
    if Keyword.get(opts, :validate_email, true) do
      changeset
      |> unsafe_validate_unique(:email, Playcode.Repo)
      |> unique_constraint(:email)
    else
      changeset
    end
  end

  @doc """
  A user changeset for changing the password.

  ## Options

    * `:hash_password` - Hashes the password so it can be stored securely
      in the database and ensures the password field is cleared to prevent
      leaks in the logs. If password hashing is not needed and clearing the
      password field is not desired (like when using this changeset for
      validations on a LiveView form), this option can be set to `false`.
      Defaults to `true`.
  """
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end

  @doc """
  A user changeset for changing the role. Only admins should use this.
  """
  def role_changeset(user, attrs) do
    user
    |> cast(attrs, [:role])
    |> validate_required([:role])
  end

  @doc """
  Verifies the password.

  If there is no user or the user doesn't have a password, we call
  `Bcrypt.no_user_verify/0` to avoid timing attacks.
  """
  def valid_password?(%Playcode.Accounts.User{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end

  @doc """
  Validates the current password otherwise adds an error to the changeset.
  """
  def validate_current_password(changeset, password) do
    changeset = cast(changeset, %{current_password: password}, [:current_password])

    if valid_password?(changeset.data, password) do
      changeset
    else
      add_error(changeset, :current_password, "is not valid")
    end
  end
end
