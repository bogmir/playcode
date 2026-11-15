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

  test "import_tei keeps a play edited by hand unless told to overwrite the edits", %{dir: dir} do
    File.write!(
      Path.join(dir, "REL0001_Primera.xml"),
      tei(code: "REL0001", title: "Primera", front: ~s(<div type="licencia"><p>P.</p></div>))
    )

    capture_io(fn -> Release.import_tei(dir) end)
    [play] = Catalogue.list_plays()
    Playcode.TestFixtures.age_rows!(play)
    [paratext] = Catalogue.list_paratexts(play.id)
    {:ok, _} = Catalogue.update_paratext(paratext, %{kind: "noticia_representacion"})

    assert capture_io(fn -> Release.import_tei(dir, dry_run: true, force: true) end) =~
             "REL0001  would be skipped"

    assert capture_io(fn -> Release.import_tei(dir, force: true) end) =~ "imported 0, skipped 1"

    assert capture_io(fn -> Release.import_tei(dir, force: true, overwrite_edits: true) end) =~
             "imported 1, skipped 0"
  end

  test "export_tei writes each play's TEI as DIR/CODE.xml, or one play's under code:" do
    play = import_tei!(tei(code: "REL0002_Segunda"))
    out_dir = Path.join(System.tmp_dir!(), "release-out-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(out_dir) end)

    assert capture_io(fn -> Release.export_tei(out_dir, code: play.code) end) =~
             "wrote 1 file(s) to #{out_dir}"

    assert File.read!(Path.join(out_dir, "REL0002_Segunda.xml")) ==
             Playcode.Export.TeiXml.generate(Catalogue.get_play_with_all!(play.id))
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

  # A play stored before this branch counted only its numbered verses (an unnumbered play 0);
  # settling recounts its numbers, so its verse count is counted again with them. The count is
  # aged through Repo: no public function writes a stale one.
  test "settle_numbering counts a play's verses again" do
    alias Playcode.Repo
    import Ecto.Query

    play =
      import_tei!(
        tei(
          encoding_desc: manual_numbering(),
          body:
            ~s(<div1 type="acto" n="1"><head>Acto I</head><sp><speaker>ANA</speaker><l>a</l><l>b</l></sp></div1>)
        )
      )

    Repo.update_all(from(p in Catalogue.Play, where: p.id == ^play.id), set: [verse_count: 0])

    capture_io(fn -> Release.settle_numbering() end)

    assert Catalogue.get_play!(play.id).verse_count == 2
  end
end
