defmodule Playcode.Performances.Actor do
  @moduledoc """
  An actor named in a performance's cast, shared by every cast row that names them. A
  nickname stands for a name when there is no surname ("Molière", "Gros-René"); `sex` is
  `"man"`, `"woman"` or nil (FileMaker's "desconocido"). Two actors never share all three
  names, compared ignoring case; the sex is not part of who an actor is, so the same names
  with and without a sex are one actor.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, only: [from: 2, where: 3]

  alias Playcode.Repo
  alias Playcode.Text

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @names ~w(surname forename nickname)a
  @fields @names ++ [:sex]

  schema "performance_actors" do
    field :surname, :string
    field :forename, :string
    field :nickname, :string
    field :sex, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(actor, attrs) do
    actor
    |> cast(attrs, @fields)
    |> squeeze_names()
    |> validate_inclusion(:sex, ~w(man woman))
    |> validate_named()
    |> validate_not_taken()
  end

  @doc """
  The other actor with the changeset's three names, or nil. An actor never twins itself.
  """
  def twin(%Ecto.Changeset{} = changeset) do
    Enum.reduce(@names, from(a in __MODULE__, limit: 1), fn field, query ->
      value = get_field(changeset, field) || ""

      where(
        query,
        [a],
        fragment("lower(coalesce(?, ''))", field(a, ^field)) == fragment("lower(?)", ^value)
      )
    end)
    |> exclude_self(changeset.data.id)
    |> Repo.one()
  end

  @doc """
  How an actor reads: forename and surname, then the nickname in quotes after a comma
  ("Jean François Poquelin, “Molière”"); a nickname alone, alone ("Rosimond").
  """
  def display_name(%__MODULE__{} = actor) do
    name = [actor.forename, actor.surname] |> Enum.reject(&is_nil/1) |> Enum.join(" ")

    case {name, actor.nickname} do
      {"", nickname} -> nickname
      {name, nil} -> name
      {name, nickname} -> "#{name}, “#{nickname}”"
    end
  end

  @doc """
  The actor of `actors` whose `display_name/1` is `name` (squeezed), ignoring case, or nil.
  """
  def named(actors, name) do
    with name when is_binary(name) <- Text.squeeze(name) do
      wanted = String.downcase(name)
      Enum.find(actors, &(String.downcase(display_name(&1)) == wanted))
    end
  end

  defp squeeze_names(changeset) do
    Enum.reduce(@names, changeset, fn field, cs ->
      update_change(cs, field, &Text.squeeze/1)
    end)
  end

  defp validate_named(changeset) do
    if get_field(changeset, :surname) || get_field(changeset, :nickname),
      do: changeset,
      else: add_error(changeset, :surname, "needs a surname or a nickname")
  end

  # ponytail: no unique index behind this, so two curators saving the same new actor in the
  # same instant can both pass; an index on the four lowered fields if that ever happens.
  defp validate_not_taken(changeset) do
    if twin(changeset),
      do: add_error(changeset, :surname, "is already another actor"),
      else: changeset
  end

  defp exclude_self(query, nil), do: query
  defp exclude_self(query, id), do: where(query, [a], a.id != ^id)
end
