defmodule Playcode.Places.Authority.Stub do
  @moduledoc """
  The authority the test environment uses. Deterministic, offline, and deliberately
  small: two known entities and an error trigger, which is everything the LiveView
  tests need to exercise the happy path and the failure path.
  """

  @behaviour Playcode.Places.Authority

  @entities %{
    "Q220" => %{
      labels: %{"es" => "Roma", "en" => "Rome", "it" => "Roma"},
      latitude: 41.9028,
      longitude: 12.4964,
      type_hint: "city",
      parent: %{id: "Q38", label: "Italia"},
      url: "https://www.wikidata.org/wiki/Q220"
    },
    "Q1136668" => %{
      labels: %{"es" => "Atlántida", "en" => "Atlantis"},
      latitude: nil,
      longitude: nil,
      type_hint: nil,
      parent: nil,
      url: "https://www.wikidata.org/wiki/Q1136668"
    }
  }

  @impl true
  def search(term, _opts \\ [])
  def search("boom", _opts), do: {:error, :unavailable}
  def search(term, _opts) when term in [nil, ""], do: {:ok, []}

  def search(term, _opts) do
    results =
      for {id, entity} <- @entities,
          label = entity.labels["es"],
          String.contains?(String.downcase(label), String.downcase(term)),
          do: %{id: id, label: label, description: "stubbed"}

    {:ok, Enum.sort_by(results, & &1.id)}
  end

  @impl true
  def fetch(id) do
    case Map.fetch(@entities, id) do
      {:ok, entity} -> {:ok, entity}
      :error -> {:error, :not_found}
    end
  end
end
