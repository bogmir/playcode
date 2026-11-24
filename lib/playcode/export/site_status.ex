defmodule Playcode.Export.SiteStatus do
  @moduledoc """
  Where a play stands on the live site: the plays the last deploy published, or, where
  no deploy repository is configured, the site as built. Each play is in one of five
  states, read from its `content_version` against the live one.
  """

  alias Playcode.Export.StaticSite
  alias Playcode.Export.StaticSite.Deployer

  @type state :: :draft | :waiting | :changed | :leaving | :live

  @doc "Each code on the live site with the `content_version` it went out with."
  def live(dir \\ StaticSite.output_dir()) do
    if Deployer.target(), do: StaticSite.deployed_plays(dir), else: StaticSite.built_plays(dir)
  end

  @spec state(map, %{String.t() => integer}) :: state
  def state(play, live) do
    published? = play.is_complete and is_nil(play.deleted_at)

    case {published?, Map.fetch(live, play.code)} do
      {false, :error} -> :draft
      {false, {:ok, _}} -> :leaving
      {true, :error} -> :waiting
      {true, {:ok, version}} when version == play.content_version -> :live
      {true, {:ok, _}} -> :changed
    end
  end
end
