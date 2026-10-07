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

  # The site is in English, so only an English translation can change a page. The Spanish
  # ones are the admin's; editing one made the whole site look changed.
  test "an English translation changes the fingerprint; a Spanish one does not" do
    dir = Path.join(System.tmp_dir!(), "fingerprint-#{System.unique_integer([:positive])}")
    File.cp_r!(Application.app_dir(:playcode, "priv/gettext"), dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    current = fn -> Fingerprint.current(version: "1.0", gettext_dir: dir) end
    before = current.()

    translate(dir, "es", "Deploy", "Publicar", "Publicar ya")
    assert current.() == before

    translate(dir, "en", "Deploy", "", "Ship")
    assert current.() != before
  end

  defp translate(dir, locale, msgid, from, to) do
    path = Path.join([dir, locale, "LC_MESSAGES", "default.po"])
    old = ~s(msgid "#{msgid}"\nmsgstr "#{from}"\n)
    po = File.read!(path)
    assert po =~ old
    File.write!(path, String.replace(po, old, ~s(msgid "#{msgid}"\nmsgstr "#{to}"\n)))
  end

  # What these return is play data, which plays.content_version tracks. Ecto schemas
  # count too. The Gettext backend's English translations are fingerprinted as data.
  @data_access [Playcode.Catalogue, Playcode.PlayContent, Playcode.Repo, PlaycodeWeb.Gettext]

  test "every module the export calls is in the fingerprint, or only reads play data" do
    reached = reach(Fingerprint.modules(), MapSet.new())
    assert Enum.reject(reached, &(&1 in Fingerprint.modules() or data_access?(&1))) == []
  end

  # A schema is play data, but a function on it can decide what a page shows: the order of
  # a bibliography's sections is Bibliography.Entry.kinds/0. Found by the S4 review.
  test "a schema the export calls a function of is in the fingerprint" do
    called =
      for module <- Fingerprint.modules(),
          {callee, function, _arity} <- imports(module),
          callee not in Fingerprint.modules(),
          callee in Application.spec(:playcode, :modules),
          Code.ensure_loaded!(callee) && function_exported?(callee, :__schema__, 1),
          # Struct and schema reflection, and changesets, which only write.
          not String.starts_with?(Atom.to_string(function), "__"),
          not String.ends_with?(Atom.to_string(function), "changeset"),
          uniq: true,
          do: {callee, function}

    assert called == []
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
    for {callee, _function, _arity} <- imports(module), callee in ours, uniq: true, do: callee
  end

  defp imports(module) do
    {:ok, {^module, [imports: imports]}} = :beam_lib.chunks(:code.which(module), [:imports])
    imports
  end
end
