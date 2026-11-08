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

    assert capture_io(fn -> Release.import_tei(dir, force: true, resume: true) end) =~
             "imported 0, skipped 1"
  end

  # Every play stored before the numbering rule came in Manual (the migration); this detects
  # each one's rule, as an import of its file would (numbering spec, "Plays already stored").
  test "settle_numbering reports a dry run, then settles every stored play's rule" do
    act =
      &~s(<div1 type="acto" n="1"><head>Acto I</head><sp><speaker>ANA</speaker>#{&1}</sp></div1>)

    numbered =
      import_tei!(
        tei(
          encoding_desc: manual_numbering(),
          body: act.(~s(<l n="1">a</l><l n="2">b</l><l n="3">c</l>))
        )
      )

    bare = import_tei!(tei(encoding_desc: manual_numbering(), body: act.("<l>a</l><l>b</l>")))

    rule =
      &{Catalogue.get_play!(&1.id).numbering_type, Catalogue.get_play!(&1.id).numbering_manual}

    out = capture_io(fn -> Release.settle_numbering(dry_run: true) end)

    assert out =~ "#{numbered.code}  V never"
    assert out =~ "#{bare.code}  V never, numbers added"
    assert out =~ "dry run, nothing written"
    assert rule.(numbered) == {"V", true}

    capture_io(fn -> assert Release.settle_numbering() == %{"V never" => 2} end)

    assert rule.(numbered) == {"V", false}
    assert rule.(bare) == {"V", false}

    assert for({attrs, _} <- xml_lines(export_tei(bare), "l"), do: attrs["n"]) == ["1", "2"]
  end
end
