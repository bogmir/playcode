defmodule Playcode.ReleaseTest do
  @moduledoc """
  The functions an operator runs on Fly with `bin/playcode rpc`, where there is no mix.
  Each prints what the matching mix task prints; the mix tasks' own tests cover the rules.
  """
  use Playcode.DataCase, async: true

  import ExUnit.CaptureIO
  import Playcode.ImportHelpers

  alias Playcode.Catalogue
  alias Playcode.Release

  setup do
    dir = Path.join(System.tmp_dir!(), "release-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    File.write!(Path.join(dir, "REL0001_Primera.xml"), tei(code: "REL0001", title: "Primera"))
    %{dir: dir}
  end

  test "import_tei reports a dry run, then imports the directory's TEI files", %{dir: dir} do
    out = capture_io(fn -> Release.import_tei(dir, dry_run: true) end)

    assert out =~ "1 file(s) in #{dir}"
    assert out =~ "REL0001  new"
    assert out =~ "dry run, nothing written"
    assert Catalogue.list_plays() == []

    assert capture_io(fn -> Release.import_tei(dir) end) =~ "imported 1, skipped 0, failed 0"
    assert [%{title: "Primera"}] = Catalogue.list_plays()

    assert capture_io(fn -> Release.import_tei(dir, force: true) end) =~ "imported 1, skipped 0"
  end
end
