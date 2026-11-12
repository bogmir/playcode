defmodule Playcode.Export.StaticSite.FingerprintTest do
  @moduledoc """
  The site fingerprint: one hash of everything the static pages are built with but the
  play data. When it differs from the one a site was built with, Generate rebuilds every
  play.
  """
  use ExUnit.Case, async: true

  import Playcode.ModuleReach

  alias Playcode.Export.StaticSite.Fingerprint

  test "the same settings give the same fingerprint, another version another" do
    assert Fingerprint.current(version: "1.0") == Fingerprint.current(version: "1.0")
    assert Fingerprint.current(version: "1.0") != Fingerprint.current(version: "1.1")
  end

  # No page embeds anything of priv/static_site but its fixed paths, so a change there
  # alone must not make every play look changed: assets have a hash of their own.
  test "the asset files change the assets' hash, not the site fingerprint" do
    [a, b] =
      for css <- ["body {}", "body { color: red }"] do
        dir = Path.join(System.tmp_dir!(), "assets-#{System.unique_integer([:positive])}")
        File.cp_r!(Application.app_dir(:playcode, "priv/static_site"), dir)
        File.write!(Path.join(dir, "style.css"), css)
        on_exit(fn -> File.rm_rf!(dir) end)
        dir
      end

    assert Fingerprint.assets(assets_dir: a) != Fingerprint.assets(assets_dir: b)

    assert Fingerprint.current(version: "1.0", assets_dir: a) ==
             Fingerprint.current(version: "1.0", assets_dir: b)
  end

  # The site prints its interface in Spanish and English, so a translation of a message its
  # code asks for changes a page, in either language. The admin's own messages do not:
  # editing one made the whole site look changed.
  test "a translation the site prints changes the fingerprint; the admin's alone does not" do
    dir = Path.join(System.tmp_dir!(), "fingerprint-#{System.unique_integer([:positive])}")
    File.cp_r!(Application.app_dir(:playcode, "priv/gettext"), dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    current = fn -> Fingerprint.current(version: "1.0", gettext_dir: dir) end
    before = current.()

    translate(dir, "es", "Deploy", "Publicar", "Publicar ya")
    translate(dir, "en", "Deploy", "", "Ship")
    assert current.() == before

    translate(dir, "es", "Skip to content", "Saltar al contenido", "Ir al contenido")
    spanish = current.()
    assert spanish != before

    translate(dir, "en", "Skip to content", "", "Skip to the text")
    assert current.() != spanish
  end

  # The rule above matches the .po references against each module's source file, which
  # `mix release` strips from the beams unless told to keep it: without it no translation
  # reached production's fingerprint.
  test "a release keeps the source file each fingerprinted module names" do
    assert Mix.Project.config()[:releases][:playcode][:strip_beams][:keep] == ["CInf"]
  end

  defp translate(dir, locale, msgid, from, to) do
    path = Path.join([dir, locale, "LC_MESSAGES", "default.po"])
    old = ~s(msgid "#{msgid}"\nmsgstr "#{from}"\n)
    po = File.read!(path)
    assert po =~ old
    File.write!(path, String.replace(po, old, ~s(msgid "#{msgid}"\nmsgstr "#{to}"\n)))
  end

  # Pushing the site and hashing it shape no page, but their names put them among the
  # StaticSite modules: a change to the deploy rebuilt all 371 plays.
  test "the deploy and the fingerprint itself are left out of it" do
    for module <- [Playcode.Export.StaticSite.Deployer, Fingerprint] do
      refute module in Fingerprint.modules()
      assert module in Fingerprint.left_out()
    end
  end

  test "every module the export calls is in the fingerprint, or only reads play data" do
    modules = Fingerprint.modules()

    assert modules
           |> reach(modules)
           |> Enum.reject(&(&1 in modules or &1 in Fingerprint.left_out() or data_access?(&1))) ==
             []
  end

  # A schema is play data, but a function on it can decide what a page shows: the order of
  # a bibliography's sections is Bibliography.Entry.kinds/0. Found by the S4 review.
  test "a schema the export calls a function of is in the fingerprint" do
    assert schema_functions_called(Fingerprint.modules()) == []
  end
end
