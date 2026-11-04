defmodule Playcode.ModuleReach do
  @moduledoc """
  The modules of this app that a set of modules reaches through its remote calls, read
  from the compiled BEAM files: what a cache key or a fingerprint must hash, so that a
  change to the code reaches what it shapes. The site fingerprint and the PDF cache key
  are each checked with it.

  The walk stops at data access, whose results the plays' `content_version` tracks: the
  contexts that read plays, the Repo, the Gettext backend and every Ecto schema. A
  hashed module is walked through even when it is one of those.
  """

  # What these return is play data. The Gettext backend's English translations are
  # fingerprinted as data.
  @data_access [Playcode.Catalogue, Playcode.PlayContent, Playcode.Repo, PlaycodeWeb.Gettext]

  @doc "Every module of this app `roots` reach, `roots` included, stopping at data access."
  def reach(roots, hashed), do: reach(roots, hashed, MapSet.new())

  defp reach([], _hashed, seen), do: seen

  defp reach([module | rest], hashed, seen) do
    cond do
      module in seen ->
        reach(rest, hashed, seen)

      module not in hashed and data_access?(module) ->
        reach(rest, hashed, MapSet.put(seen, module))

      true ->
        reach(rest ++ calls(module), hashed, MapSet.put(seen, module))
    end
  end

  @doc "Whether `module` only reads play data: a play context, the Repo, Gettext, a schema."
  def data_access?(module) do
    Code.ensure_loaded!(module)
    module in @data_access or function_exported?(module, :__schema__, 1)
  end

  @doc """
  The `{schema, function}` pairs the `hashed` modules call on a schema left out of them. A
  schema is play data, but a function on it can decide what is printed: the order of a
  bibliography's sections is `Bibliography.Entry.kinds/0`. Struct and schema reflection,
  and changesets, which only write, are not counted.
  """
  def schema_functions_called(hashed) do
    for module <- hashed,
        {callee, function, _arity} <- imports(module),
        callee not in hashed,
        callee in Application.spec(:playcode, :modules),
        Code.ensure_loaded!(callee) && function_exported?(callee, :__schema__, 1),
        not String.starts_with?(Atom.to_string(function), "__"),
        not String.ends_with?(Atom.to_string(function), "changeset"),
        uniq: true,
        do: {callee, function}
  end

  # This app's modules that `module` calls.
  defp calls(module) do
    ours = Application.spec(:playcode, :modules)
    for {callee, _function, _arity} <- imports(module), callee in ours, uniq: true, do: callee
  end

  defp imports(module) do
    {:ok, {^module, [imports: imports]}} = :beam_lib.chunks(:code.which(module), [:imports])
    imports
  end
end
