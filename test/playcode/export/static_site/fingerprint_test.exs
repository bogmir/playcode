defmodule Playcode.Export.StaticSite.FingerprintTest do
  @moduledoc """
  The site fingerprint: one hash of everything the static pages are built with but the
  play data. When it differs from the one a site was built with, Generate rebuilds every
  play.
  """
  use ExUnit.Case, async: true

  alias Playcode.Export.StaticSite.Fingerprint

  test "the same settings give the same fingerprint, another version another" do
    assert Fingerprint.current(version: "1.0") == Fingerprint.current(version: "1.0")
    assert Fingerprint.current(version: "1.0") != Fingerprint.current(version: "1.1")
  end

  # What these return is play data, which plays.content_version tracks. Ecto schemas
  # count too.
  @data_access [Playcode.Catalogue, Playcode.PlayContent, Playcode.Repo]

  test "every module the export calls is in the fingerprint, or only reads play data" do
    reached = reach(Fingerprint.modules(), MapSet.new())
    assert Enum.reject(reached, &(&1 in Fingerprint.modules() or data_access?(&1))) == []
  end

  # Follows the remote calls out of the fingerprinted modules, through every module of
  # this app they reach, stopping at data access.
  defp reach([], seen), do: seen

  defp reach([module | rest], seen) do
    cond do
      module in seen ->
        reach(rest, seen)

      module not in Fingerprint.modules() and data_access?(module) ->
        reach(rest, MapSet.put(seen, module))

      true ->
        reach(rest ++ calls(module), MapSet.put(seen, module))
    end
  end

  defp data_access?(module) do
    Code.ensure_loaded!(module)
    module in @data_access or function_exported?(module, :__schema__, 1)
  end

  # This app's modules that `module` calls, from the imports in its compiled BEAM file.
  defp calls(module) do
    ours = Application.spec(:playcode, :modules)
    {:ok, {^module, [imports: imports]}} = :beam_lib.chunks(:code.which(module), [:imports])
    for {callee, _function, _arity} <- imports, callee in ours, uniq: true, do: callee
  end
end
