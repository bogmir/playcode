defmodule Mix.Tasks.PlaycodeTasksTest do
  @moduledoc """
  The mix tasks, run the way an operator runs them: `Mix.Task.rerun/2` with
  command-line arguments, reading what they print.
  """
  # Mix.shell/1 is global to the VM, so these cannot run beside other tests.
  use PlaycodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions
  import Playcode.TestFixtures
  import Playcode.ImportHelpers

  alias Playcode.Accounts
  alias Playcode.ActivityLog
  alias Playcode.Bibliography
  alias Playcode.Catalogue
  alias Playcode.Performances
  alias Playcode.PlayContent
  alias Playcode.Places
  alias Playcode.Witnesses

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
  end

  defp run(task, args) do
    Mix.Task.rerun(task, args)
    output()
  end

  defp output(acc \\ []) do
    receive do
      {:mix_shell, _level, [line]} -> output([line | acc])
    after
      0 -> acc |> Enum.reverse() |> Enum.join("\n")
    end
  end

  defp tmp_dir do
    dir = Path.join(System.tmp_dir!(), "task-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    dir
  end

  defp witness_lines(play),
    do: play.id |> Witnesses.list_for_play() |> Enum.map(&Witnesses.plain/1)

  defp citations(play) do
    play.id
    |> Bibliography.list_links()
    |> Enum.map(&Playcode.Bibliography.Citation.plain(&1.entry, &1))
  end

  describe "playcode.invite" do
    # The break-glass path: on a fresh deployment with no SMTP, this is the only way
    # the first admin gets in.
    test "--print-url prints a link that lets the invitee set a password", %{conn: conn} do
      out = run("playcode.invite", ["jefa@uv.es", "--admin", "--print-url"])

      assert [path] = Regex.run(~r{/users/accept-invite/\S+}, out)
      refute_email_sent()
      assert Accounts.get_user_by_email("jefa@uv.es").role == :admin

      {:ok, lv, _html} = live(conn, path)
      assert has_element?(lv, "form")
    end

    test "without --print-url the link is mailed" do
      assert run("playcode.invite", ["nuevo@uv.es"]) =~ "invitation sent to nuevo@uv.es"
      assert_email_sent(to: "nuevo@uv.es")
    end

    test "an address with an active account is refused" do
      user = user_fixture()

      assert_raise Mix.Error, ~r/already has an active account/, fn ->
        Mix.Task.rerun("playcode.invite", [user.email])
      end
    end
  end

  describe "playcode.import.tei" do
    setup do
      dir = tmp_dir()
      File.write!(Path.join(dir, "TASK0001_Primera.xml"), tei(code: "TASK0001", title: "Primera"))
      %{dir: dir}
    end

    test "--dry-run reports what it would import and writes nothing", %{dir: dir} do
      out = run("playcode.import.tei", ["--dir", dir, "--dry-run"])

      assert out =~ "TASK0001  new"
      assert out =~ "dry run, nothing written"
      assert Catalogue.list_plays() == []
    end

    test "--dry-run lists the references an import would add", %{dir: dir} do
      File.write!(
        Path.join(dir, "TASK0003_Tercera.xml"),
        tei(
          code: "TASK0003",
          title: "Tercera",
          back:
            ~s(<div type="bibliografia"><listBibl type="critica"><biblStruct type="libro"><monogr>) <>
              ~s(<author>Autor, Ana</author><title level="m">Libro nuevo</title><imprint><date/></imprint>) <>
              ~s(</monogr></biblStruct></listBibl></div>)
        )
      )

      out = run("playcode.import.tei", ["--dir", dir, "--dry-run"])

      assert out =~ "TASK0003  new, adds 1 reference(s)"
      assert out =~ ~r/\n\s+\+ Autor, Ana\. Libro nuevo/
    end

    test "--dry-run lists the references an import would skip", %{dir: dir} do
      File.write!(
        Path.join(dir, "TASK0004_Cuarta.xml"),
        tei(
          code: "TASK0004",
          title: "Cuarta",
          back:
            ~s(<div type="bibliografia"><listBibl type="critica"><biblStruct type="libro" xml:lang="la">) <>
              ~s(<monogr><author>Autor, Ana</author><title level="m">Liber</title><imprint><date/></imprint>) <>
              ~s(</monogr></biblStruct></listBibl></div>)
        )
      )

      out = run("playcode.import.tei", ["--dir", dir, "--dry-run"])

      assert out =~ "TASK0004  new, skips 1 reference(s)"
      assert out =~ ~r/\n\s+- Autor, Ana\. Liber/
    end

    # TEI's schema checks a part's value, not its order, so a valid file can hold a last
    # part that completes nothing (EMOTHE0284's "O molto") or a first part nothing
    # completes. A split verse may cross scenes, never acts.
    test "--dry-run lists the parts of split verses out of order", %{dir: dir} do
      File.write!(
        Path.join(dir, "TASK0005_Quinta.xml"),
        tei(
          code: "TASK0005",
          title: "Quinta",
          body: """
          <div1 type="acto" n="1"><head>Acto I</head>
            <div2 type="escena"><head>Escena 1</head>
              <sp><speaker>A</speaker><p>Prosa.</p></sp>
              <sp><speaker>B</speaker><lg><l xml:id="q-0001" part="F">O molto</l></lg></sp>
              <sp><speaker>C</speaker><lg><l xml:id="q-0002" n="1" part="I">Abre el verso</l></lg></sp>
            </div2>
            <div2 type="escena"><head>Escena 2</head>
              <sp><speaker>D</speaker><lg><l xml:id="q-0003" part="F">y lo cierra en otra escena</l><l xml:id="q-0004" n="2" part="I">Sei qui, fratello?</l></lg></sp>
              <sp><speaker>E</speaker><p>Prosa.</p></sp>
              <sp><speaker>F</speaker><lg><l xml:id="q-0005" n="3">Un verso entero.</l><l xml:id="q-0006" part="M">Hippolita!</l></lg></sp>
            </div2>
          </div1>
          """
        )
      )

      out = run("playcode.import.tei", ["--dir", dir, "--dry-run"])

      assert out =~ "TASK0005  new, 3 split-verse part(s) out of order"
      assert out =~ ~r/\n\s+! q-0001 last part, completes no verse: O molto\n/
      assert out =~ ~r/\n\s+! q-0004 first part, never completed: Sei qui, fratello\?\n/
      assert out =~ ~r/\n\s+! q-0006 middle part, completes no verse: Hippolita!\n/
      refute out =~ "q-0002"
      refute out =~ "q-0003"
    end

    test "imports once, skips on the next run, and re-imports under --force", %{dir: dir} do
      assert run("playcode.import.tei", ["--dir", dir]) =~ "imported 1, skipped 0, failed 0"
      assert [%{title: "Primera"}] = Catalogue.list_plays()

      File.write!(Path.join(dir, "TASK0001_Primera.xml"), tei(code: "TASK0001", title: "Segunda"))

      assert run("playcode.import.tei", ["--dir", dir]) =~ "imported 0, skipped 1, failed 0"
      assert [%{title: "Primera"}] = Catalogue.list_plays()

      assert run("playcode.import.tei", ["--dir", dir, "--force"]) =~ "imported 1"
      assert [%{title: "Segunda"}] = Catalogue.list_plays()
    end

    # A forced run on Fly stopped part way twice. Under --resume it skips a play imported
    # since its file was written, so running the same command again carries on where the
    # last one stopped; a play never imported, or one that failed, is imported.
    test "--force --resume skips a play imported since its file was written", %{dir: dir} do
      path = Path.join(dir, "TASK0001_Primera.xml")
      File.touch!(path, System.os_time(:second) - 60)
      run("playcode.import.tei", ["--dir", dir])
      File.write!(Path.join(dir, "TASK0002_Segunda.xml"), tei(code: "TASK0002"))

      assert run("playcode.import.tei", ["--dir", dir, "--force", "--resume"]) =~
               "imported 1, skipped 1, failed 0"

      File.touch!(path, System.os_time(:second) + 60)

      assert run("playcode.import.tei", ["--dir", dir, "--force", "--resume"]) =~
               "imported 1, skipped 1, failed 0"

      assert run("playcode.import.tei", ["--dir", dir, "--force"]) =~ "imported 2"
    end

    # A forced re-import replaces a play's text, so the dry run names the plays whose text
    # was edited by hand after their last import. The edit is logged here the way the
    # content editor logs it; the editor itself is tested on its own page.
    test "--dry-run --force counts the hand edits a re-import would undo", %{dir: dir} do
      run("playcode.import.tei", ["--dir", dir])
      [play] = Catalogue.list_plays()
      refute run("playcode.import.tei", ["--dir", dir, "--dry-run", "--force"]) =~ "hand edit"

      for type <- ~w(element note) do
        ActivityLog.log!(%{play_id: play.id, action: "update", resource_type: type})
      end

      out = run("playcode.import.tei", ["--dir", dir, "--dry-run", "--force"])

      assert out =~ ~r/TASK0001  replaces .*, undoes 2 hand edit\(s\) to its text/
      assert out =~ "1 with hand edits since their last import"
    end

    # The rows a forced re-import replaces, counted by when they changed rather than by
    # the activity log, so an edit to any of the file's rows shows.
    test "--dry-run --force counts the file's rows edited since their import", %{dir: dir} do
      File.write!(
        Path.join(dir, "TASK0001_Primera.xml"),
        tei(code: "TASK0001", front: ~s(<div type="licencia"><p>Privilège.</p></div>))
      )

      run("playcode.import.tei", ["--dir", dir])
      [play] = Catalogue.list_plays()
      refute run("playcode.import.tei", ["--dir", dir, "--dry-run", "--force"]) =~ "edited since"

      play |> Playcode.TestFixtures.age_rows!()
      [paratext] = Catalogue.list_paratexts(play.id)
      {:ok, _} = Catalogue.update_paratext(paratext, %{kind: "noticia_representacion"})

      assert run("playcode.import.tei", ["--dir", dir, "--dry-run", "--force"]) =~
               ~r/TASK0001  replaces .*, 1 row\(s\) from the file edited since their import/
    end

    # A later list's line keeps its own description: an edit to it changes no character.
    test "--dry-run --force counts a cast list's line edited since its import", %{dir: dir} do
      File.write!(
        Path.join(dir, "TASK0001_Primera.xml"),
        tei(
          code: "TASK0001",
          front:
            ~s(<div type="elenco"><head>PERSONAS</head><castList><castItem><role xml:id="ANA">ANA</role></castItem></castList></div>) <>
              ~s(<div type="elenco"><head>OTRAS</head><castList><castItem><role corresp="#ANA">ANA</role></castItem></castList></div>)
        )
      )

      run("playcode.import.tei", ["--dir", dir])
      [play] = Catalogue.list_plays()
      play |> Playcode.TestFixtures.age_rows!()

      [_first, second] = Playcode.PlayContent.list_cast_lists(play.id)
      [line] = second.entries
      {:ok, _} = Playcode.PlayContent.update_entry(line, %{description: "disfrazada"})

      assert run("playcode.import.tei", ["--dir", dir, "--dry-run", "--force"]) =~
               ~r/TASK0001  replaces .*, 1 row\(s\) from the file edited since their import/
    end

    test "an import logs itself, so edits made before it are not counted again", %{dir: dir} do
      run("playcode.import.tei", ["--dir", dir])
      [play] = Catalogue.list_plays()
      ActivityLog.log!(%{play_id: play.id, action: "update", resource_type: "element"})

      run("playcode.import.tei", ["--dir", dir, "--force"])

      refute run("playcode.import.tei", ["--dir", dir, "--dry-run", "--force"]) =~ "hand edit"
    end

    test "one unreadable file does not stop the rest", %{dir: dir} do
      File.write!(Path.join(dir, "TASK0002_Rota.xml"), "<TEI><teiHeader>")

      out = run("playcode.import.tei", ["--dir", dir])

      assert out =~ "imported 1, skipped 0, failed 1"
      assert out =~ "TASK0002"
    end
  end

  describe "playcode.import.filemaker" do
    @export "test/fixtures/filemaker/export_sample.ndjson"

    setup do
      %{play: play_fixture(%{"code" => "EMOTHE0038_AntonyAndCleopatra", "language" => "es"})}
    end

    test "--dry-run prints the changes and writes nothing", %{play: play} do
      out = run("playcode.import.filemaker", ["--path", @export, "--dry-run"])

      assert out =~ "EMOTHE0038"
      assert out =~ ~s(language -> "en")
      assert out =~ "dry run, nothing written"
      assert Catalogue.get_play!(play.id).language == "es"
    end

    test "without --dry-run the changes are applied", %{play: play} do
      assert run("playcode.import.filemaker", ["--path", @export]) =~ "updated 1, failed 0"
      assert Catalogue.get_play!(play.id).language == "en"
    end

    # Same rule as every Catalogue read.
    test "an archived play is left out", %{play: play} do
      {:ok, _} = Catalogue.delete_play(play)

      out = run("playcode.import.filemaker", ["--path", @export])

      refute out =~ "EMOTHE0038"
      assert out =~ "updated 0, failed 0"
      assert Catalogue.get_play!(play.id, include_deleted: true).language == "es"
    end

    test "a malformed record refuses the export, naming the record" do
      for {fixture, record} <- [{"malformed_version", "1"}, {"malformed_fields", "7"}] do
        assert_raise Mix.Error, ~r/record #{record} is malformed/, fn ->
          Mix.Task.rerun("playcode.import.filemaker", [
            "--path",
            "test/fixtures/filemaker/#{fixture}.ndjson"
          ])
        end
      end
    end

    test "a missing export is refused" do
      assert_raise Mix.Error, ~r/cannot read/, fn ->
        Mix.Task.rerun("playcode.import.filemaker", [
          "--path",
          "test/fixtures/filemaker/nope.ndjson"
        ])
      end
    end
  end

  describe "playcode.export.site" do
    test "publishes complete plays into the given directory, and drafts only with --all" do
      complete = play_fixture(%{"is_complete" => true})
      draft = play_fixture()
      dir = tmp_dir()
      page = fn play -> File.exists?(Path.join([dir, "plays", play.code, "index.html"])) end

      run("playcode.export.site", ["-o", dir])
      assert page.(complete)
      refute page.(draft)

      run("playcode.export.site", ["-o", dir, "--all"])
      assert page.(draft)

      assert run("playcode.export.site", ["-o", dir, "--all"]) =~ "largest act page"
    end
  end

  describe "playcode.import.bibliography" do
    @dump "test/fixtures/filemaker/ctce_dades"

    setup do
      %{
        hamlet: play_fixture(%{"code" => "EMOTHE0010_Hamlet"}),
        antony: play_fixture(%{"code" => "EMOTHE0038_AntonyAndCleopatra"})
      }
    end

    test "--dry-run prints the plan and writes nothing", %{hamlet: hamlet} do
      out = run("playcode.import.bibliography", ["--path", @dump, "--dry-run"])

      assert out =~ "EMOTHE0010_Hamlet  5 links"
      assert out =~ "bibliography: 5 entries (0 already in Playcode), 6 links on 2 plays"
      assert out =~ "modern editions: 3 entries (0 already in Playcode), 4 links on 2 plays"
      assert out =~ "skipped, test_record: 1  T04:9"
      assert out =~ "links to versions not held: 1"
      assert out =~ "dry run, nothing written"
      assert Bibliography.list_links(hamlet.id) == []
    end

    test "writes each entry once, as FileMaker printed it, with each play's own pages", %{
      hamlet: hamlet,
      antony: antony
    } do
      assert run("playcode.import.bibliography", ["--path", @dump]) =~
               "created 8 entries and 10 links"

      assert "Rowe, Nicholas, ed. Hamlet. Shakespeare, William. In: The Works of Mr. William Shakespeare. Vol. 5. London: Jacob Tonson, 1709, pp. 2366-2466, 6 vols." in citations(
               hamlet
             )

      assert "Rowe, Nicholas, ed. Hamlet. Shakespeare, William. In: The Works of Mr. William Shakespeare. Vol. 7. London: Jacob Tonson, 1709, pp. 100-200, 6 vols." in citations(
               antony
             )

      assert "Peele, George. Altweibermär. Tra. Harbecke, Ulrich J. Weinheim: Deutscher Laienspiel-Verlag, 1967. Das Bühnenspiel. (Orig: Old Wife's Tale)" in citations(
               hamlet
             )

      assert "Thompson, Ann; Taylor, Neil, ed. Hamlet. Shakespeare, William. London: Thomson Learning, 2006. The Arden Shakespeare. Third series." in citations(
               hamlet
             )

      [rowe] = for l <- Bibliography.list_links(hamlet.id), l.entry.volumes_total == "6", do: l
      assert Bibliography.link_counts([rowe.entry_id]) == %{rowe.entry_id => 2}
      assert rowe.origin == "filemaker"
    end

    test "a re-run skips a play already imported, so a removal stays removed", %{hamlet: hamlet} do
      run("playcode.import.bibliography", ["--path", @dump])
      [first | _] = Bibliography.list_links(hamlet.id)
      {:ok, _} = Bibliography.unlink(first)

      out = run("playcode.import.bibliography", ["--path", @dump])

      assert out =~ "already imported: 2 plays"
      assert out =~ "created 0 entries and 0 links"
      assert length(Bibliography.list_links(hamlet.id)) == 4
    end

    # Its references came with its TEI file: FileMaker's copies would come in beside them.
    test "a play whose bibliography came from its TEI file is left alone", %{hamlet: hamlet} do
      {:ok, _} =
        Bibliography.create_entry_for_play(
          hamlet.id,
          %{"kind" => "criticism", "monogr_title" => "Del fichero"},
          %{},
          "tei"
        )

      out = run("playcode.import.bibliography", ["--path", @dump])

      assert out =~ "already imported: 1 plays"
      assert [%{origin: "tei"}] = Bibliography.list_links(hamlet.id)
    end

    test "a play added later shares the entries already imported" do
      run("playcode.import.bibliography", ["--path", @dump])
      later = play_fixture(%{"code" => "EMOTHE0038_AntonioYCleopatra"})

      out = run("playcode.import.bibliography", ["--path", @dump])

      assert out =~ "modern editions: 2 entries (2 already in Playcode), 2 links on 1 plays"
      assert out =~ "created 0 entries and 5 links"
      assert length(Bibliography.list_links(later.id)) == 5
    end

    # Found by the final review: the "already imported" marker was the play's filemaker
    # links themselves, so removing all of them made the next run bring them back.
    test "a re-run keeps a play's removals even when every imported link was removed", %{
      hamlet: hamlet
    } do
      run("playcode.import.bibliography", ["--path", @dump])
      for link <- Bibliography.list_links(hamlet.id), do: {:ok, _} = Bibliography.unlink(link)

      out = run("playcode.import.bibliography", ["--path", @dump])

      assert out =~ "already imported: 2 plays"
      assert Bibliography.list_links(hamlet.id) == []
    end

    # Found by the final review: "Add existing" on a play imported later, then a re-run,
    # planned a second link to the same entry and rolled the whole import back.
    test "a re-run skips an entry a curator already linked to a play added later", %{
      antony: antony
    } do
      run("playcode.import.bibliography", ["--path", @dump])
      later = play_fixture(%{"code" => "EMOTHE0038_AntonioYCleopatra"})
      [rowe] = for l <- Bibliography.list_links(antony.id), l.entry.volumes_total == "6", do: l
      {:ok, _} = Bibliography.link_entry(later.id, rowe.entry_id)

      dry = run("playcode.import.bibliography", ["--path", @dump, "--dry-run"])
      assert dry =~ "skipped, already_linked: 1  T04:52 on EMOTHE0038_AntonioYCleopatra"

      assert run("playcode.import.bibliography", ["--path", @dump]) =~
               "created 0 entries and 4 links"

      assert length(Bibliography.list_links(later.id)) == 5
    end

    test "an archived play is left out", %{antony: antony} do
      {:ok, _} = Catalogue.delete_play(antony)
      run("playcode.import.bibliography", ["--path", @dump])
      assert Bibliography.list_links(antony.id) == []
    end

    test "a missing dump is refused" do
      assert_raise Mix.Error, ~r/cannot read/, fn ->
        Mix.Task.rerun("playcode.import.bibliography", ["--path", "test/fixtures/filemaker/nope"])
      end
    end
  end

  describe "playcode.import.witnesses" do
    @witnesses "test/fixtures/filemaker/witnesses"

    setup do
      %{
        hamlet: play_fixture(%{"code" => "EMOTHE0010_Hamlet"}),
        mudarra:
          play_fixture(%{
            "code" => "EMOTHE0435_ElBastardoMudarra",
            "author_name" => "Félix Lope de Vega y Carpio"
          })
      }
    end

    test "--dry-run prints the plan and writes nothing", %{hamlet: hamlet} do
      out = run("playcode.import.witnesses", ["--path", @witnesses, "--dry-run"])

      assert out =~ "EMOTHE0010_Hamlet  2 witnesses"
      assert out =~ "witnesses: 4 on 2 plays"

      assert out =~
               "attribution dropped: 2  T03:77 on EMOTHE0435_ElBastardoMudarra, " <>
                 "T03:79 on EMOTHE0435_ElBastardoMudarra"

      assert out =~ "skipped, empty: 1  T03:15"
      assert out =~ "skipped, test_record: 1  T03:32"
      assert out =~ "witnesses on versions not held: 10"
      assert out =~ "dry run, nothing written"
      assert witness_lines(hamlet) == []
    end

    test "writes each play's witnesses in FileMaker's order, as emothe.uv.es prints them", %{
      hamlet: hamlet,
      mudarra: mudarra
    } do
      assert run("playcode.import.witnesses", ["--path", @witnesses]) =~ "created 4 witnesses"

      assert witness_lines(hamlet) == [
               "THE Tragicall Historie of HAMLET Prince of Denmarke. " <>
                 "[The Tragical History of Hamlet, Prince of Denmark]. Shakespeare, William. " <>
                 "London. Ling, Nicholas; Trundell, John. 1603. 4º. Usual abbreviation: Q1. " <>
                 "Often referred to as “bad quarto”. Printer: Simmes, Valentine.",
               "COMEDIES, HISTORIES, & TRAGEDIES. Shakespeare, William. London. " <>
                 "Blount, Edward; Smethwick, John; Jaggard, Isaac; Aspley, William. 1623. 2º. " <>
                 "Usual abbreviation: F1. Also referred to as First Folio."
             ]

      assert witness_lines(mudarra) == [
               "Veinticuatro parte perfeta de las comedias del Fénix de España Frey Lope Félix de Vega Carpio.",
               "El bastardo Mudarra: tragicomedia."
             ]

      assert [%{origin: "filemaker", filemaker_id: "T03:33"} | _] =
               Witnesses.list_for_play(hamlet.id)
    end

    # As S4 learned: the play's filemaker rows alone are no marker, since a curator may
    # delete every one of them.
    test "a re-run skips a play already imported, even with every witness deleted", %{
      hamlet: hamlet
    } do
      run("playcode.import.witnesses", ["--path", @witnesses])
      for w <- Witnesses.list_for_play(hamlet.id), do: {:ok, _} = Witnesses.delete_witness(w)

      out = run("playcode.import.witnesses", ["--path", @witnesses])

      assert out =~ "already imported: 2 plays"
      assert out =~ "created 0 witnesses"
      assert witness_lines(hamlet) == []
    end

    test "an archived play is left out", %{mudarra: mudarra} do
      {:ok, _} = Catalogue.delete_play(mudarra)
      run("playcode.import.witnesses", ["--path", @witnesses])
      assert witness_lines(mudarra) == []
    end

    test "a missing dump is refused" do
      assert_raise Mix.Error, ~r/cannot read/, fn ->
        Mix.Task.rerun("playcode.import.witnesses", ["--path", "test/fixtures/filemaker/nope"])
      end
    end
  end

  describe "playcode.import.places" do
    @places "test/fixtures/filemaker/places"

    @place_plays ~w(
      EMOTHE0005_LAminta EMOTHE0006_IlPastorFido EMOTHE0007_LaCalandria
      EMOTHE0010_TheTragedyOfHamletPrinceOfDenmark EMOTHE0038_AntonyAndCleopatra
      EMOTHE0151_AsYouLikeIt EMOTHE0153_TheTragedyOfRomeoAndJuliet
      EMOTHE0262_TheShoemakersHoliday EMOTHE0337_TheTragedyOfMariam
      EMOTHE0354_TheBrokenHeart EMOTHE0367_Endymion EMOTHE0394_EntreBobosAndaElJuego
      EMOTHE0545_LaTraicionEnLaAmistad EMOTHE0653_TheShyCourtier
      EMOTHE0697_TheTragedyOfOthelloTheMoorOfVenice
    )

    setup do
      plays = Map.new(@place_plays, &{&1, play_fixture(%{"code" => &1})})

      %{
        plays: Map.values(plays),
        hamlet: plays["EMOTHE0010_TheTragedyOfHamletPrinceOfDenmark"],
        othello: plays["EMOTHE0697_TheTragedyOfOthelloTheMoorOfVenice"]
      }
    end

    # The lines readers see for a play's places, in order.
    defp place_lines(play) do
      gazetteer = Places.gazetteer()
      for link <- Places.list_play_places(play.id), do: Places.place_line(link, gazetteer, "es")
    end

    defp link_count(plays),
      do: plays |> Enum.map(&length(Places.list_play_places(&1.id))) |> Enum.sum()

    defp with_links(plays), do: Enum.count(plays, &(Places.list_play_places(&1.id) != []))

    test "--dry-run prints the plan and writes nothing", %{plays: plays} do
      out = run("playcode.import.places", ["--path", @places, "--dry-run"])

      assert out =~ "Roma — República romana"
      assert out =~ "dry run, nothing written"
      assert Places.list_places() == []
      assert link_count(plays) == 0
    end

    test "writes the places and the links, as readers will see them", %{
      plays: plays,
      hamlet: hamlet
    } do
      out = run("playcode.import.places", ["--path", @places])

      assert [_, places, links] = Regex.run(~r/created (\d+) places and (\d+) links/, out)
      assert String.to_integer(places) == length(Places.list_places())
      assert String.to_integer(links) == link_count(plays)

      assert place_lines(hamlet) == ["Elsinor, Reino de Dinamarca, Europa (hoy Dinamarca)"]

      origins = for play <- plays, link <- Places.list_play_places(play.id), do: link.origin
      assert Enum.uniq(origins) == ["filemaker"]

      # One log entry per play that got links.
      logged = ActivityLog.list_entries(action: "import", resource_type: "play_place")
      assert length(logged) == with_links(plays)
      assert Enum.all?(logged, &(&1.metadata == %{"source" => "filemaker"}))
    end

    test "a place the gazetteer already has is linked, not made again, and left as it was", %{
      hamlet: hamlet
    } do
      elsinor = place_fixture(%{"name" => "Elsinor"})
      names = Enum.map(elsinor.names, & &1.name)

      out = run("playcode.import.places", ["--path", @places])

      assert [link] = Places.list_play_places(hamlet.id)
      assert link.place_id == elsinor.id

      assert [_] =
               Enum.filter(Places.list_places(), &(Places.display_name(&1, "es") == "Elsinor"))

      assert %{parent_place_id: nil, names: after_names} = Places.get_place!(elsinor.id)
      assert Enum.map(after_names, & &1.name) == names

      # The place it had is not among the ones created.
      assert [_, places, _links] = Regex.run(~r/created (\d+) places and (\d+) links/, out)
      assert String.to_integer(places) == length(Places.list_places()) - 1
    end

    test "a second run changes nothing", %{plays: plays} do
      run("playcode.import.places", ["--path", @places])
      places = length(Places.list_places())
      links = link_count(plays)

      out = run("playcode.import.places", ["--path", @places])

      assert out =~ "already imported: #{with_links(plays)} plays"
      assert out =~ "created 0 places and 0 links"
      assert length(Places.list_places()) == places
      assert link_count(plays) == links
    end

    # As S3 and S4 learned: the play's filemaker links alone are no marker, since a curator
    # may delete every one of them.
    test "links a curator removed stay removed", %{hamlet: hamlet} do
      run("playcode.import.places", ["--path", @places])
      for link <- Places.list_play_places(hamlet.id), do: {:ok, _} = Places.unlink_place(link)

      run("playcode.import.places", ["--path", @places])

      assert Places.list_play_places(hamlet.id) == []
    end

    test "a play's own links stay, FileMaker's go after them", %{othello: othello} do
      own = place_fixture()
      play_place_fixture(othello, own)

      run("playcode.import.places", ["--path", @places])

      assert [first | imported] = Places.list_play_places(othello.id)
      assert {first.place_id, first.position, first.origin} == {own.id, 0, "manual"}
      assert length(imported) == 3
      assert Enum.all?(imported, &(&1.origin == "filemaker"))
      assert Enum.map(imported, & &1.position) == [1, 2, 3]
    end

    test "a missing dump is refused" do
      assert_raise Mix.Error, ~r/cannot read/, fn ->
        Mix.Task.rerun("playcode.import.places", ["--path", "test/fixtures/filemaker/nope"])
      end
    end
  end

  describe "playcode.import.performances" do
    @performances "test/fixtures/filemaker/performances"

    # The versions the sample holds, by code; 0083 stays out, for the version we do not hold.
    @performance_plays %{
      "0010" => "EMOTHE0010_Hamlet",
      "0038" => "EMOTHE0038_AntonyAndCleopatra",
      "0209" => "EMOTHE0209_Play",
      "0274" => "EMOTHE0274_Play",
      "0304" => "EMOTHE0304_TheAlchemist",
      "0309" => "EMOTHE0309_Play",
      "0313" => "EMOTHE0313_TheWayOfTheWorld",
      "0373" => "EMOTHE0373_Play",
      "0379" => "EMOTHE0379_Play",
      "0420" => "EMOTHE0420_Play",
      "0472" => "EMOTHE0472_Play",
      "0491" => "EMOTHE0491_Play",
      "0644" => "EMOTHE0644_Play",
      "0671" => "EMOTHE0671_Play",
      "0675" => "EMOTHE0675_Play",
      "0714" => "EMOTHE0714_Play"
    }

    setup do
      plays =
        Map.new(@performance_plays, fn {short, code} ->
          {short, play_fixture(%{"code" => code})}
        end)

      %{plays: plays, alchemist: plays["0304"], way: plays["0313"]}
    end

    defp performances(play), do: Performances.list_for_play(play.id)

    defp performance_count(plays),
      do: plays |> Map.values() |> Enum.map(&length(performances(&1))) |> Enum.sum()

    # The lines readers see for a play's performances, in order, and the sources they cite.
    defp performance_lines(play, locale \\ "en") do
      Performances.listing(
        performances(play),
        PlayContent.list_characters(play.id),
        Places.gazetteer(),
        locale
      )
    end

    # What a run wrote that no play's list shows: the corpus-wide rows.
    defp performance_leftovers do
      %{
        companies: Performances.list_companies(),
        actors: Performances.list_actors(),
        places: Places.list_places(),
        entries: Bibliography.search_entries("Catalogue", nil, 10, kinds: :all),
        log: ActivityLog.list_entries(action: "import", resource_type: "play_performance")
      }
    end

    test "--dry-run prints the plan and writes nothing", %{plays: plays} do
      out = run("playcode.import.performances", ["--path", @performances, "--dry-run"])

      assert out =~ "EMOTHE0304_TheAlchemist  1610  Globe or Blackfriars"
      assert out =~ "dry run, nothing written"
      assert performance_count(plays) == 0

      assert %{companies: [], actors: [], places: [], entries: [], log: []} =
               performance_leftovers()
    end

    test "writes the performances as readers will see them", %{plays: plays, alchemist: alchemist} do
      out = run("playcode.import.performances", ["--path", @performances])

      assert [_, performances, companies, actors, entries, places] =
               Regex.run(
                 ~r/created (\d+) performances, (\d+) companies, (\d+) actors, (\d+) entries and (\d+) places/,
                 out
               )

      assert String.to_integer(performances) == performance_count(plays)
      assert String.to_integer(companies) == length(Performances.list_companies())
      assert String.to_integer(actors) == length(Performances.list_actors())
      assert String.to_integer(places) == length(Places.list_places())
      assert String.to_integer(entries) > 0

      assert %{lines: [first | _] = lines, sources: [{1, wiggins}]} = performance_lines(alchemist)

      assert first.parts == [
               "Globe or Blackfriars",
               "London, Kingdom of England, Europe (today United Kingdom)",
               "The King’s Men",
               "commercial theatre"
             ]

      # performance 260 cites a record that names its volume and no page, 263 one with a page
      assert first.range == "vol. 6"
      assert Enum.any?(lines, &(&1.range == "vol. 6, p. 83"))
      assert wiggins.kind == "catalogue"

      origins = for play <- Map.values(plays), p <- performances(play), do: p.origin
      assert Enum.uniq(origins) == ["filemaker"]

      # FileMaker's record, for the imports' own bookkeeping: no TEI file names it
      assert [%{filemaker_id: "T11:260"} | _] = performances(alchemist)

      # Entries a performance cites stay out of the play's bibliography.
      assert Bibliography.list_links(alchemist.id) == []

      # One log entry per play that got performances.
      logged = ActivityLog.list_entries(action: "import", resource_type: "play_performance")
      assert length(logged) == Enum.count(Map.values(plays), &(performances(&1) != []))
      assert Enum.all?(logged, &(&1.metadata == %{"source" => "filemaker"}))
    end

    test "gives a performance its place, its cast and the cast list", %{plays: plays, way: way} do
      run("playcode.import.performances", ["--path", @performances])

      assert %{lines: lines} = performance_lines(plays["0671"], "es")
      assert Enum.any?(lines, fn line -> Enum.any?(line.parts, &(&1 =~ "Nápoles")) end)

      assert %{lines: [%{cast: [molière, _]} | _]} = performance_lines(plays["0714"])
      assert molière == "Jean François Poquelin, “Molière” (Argan)"

      assert [%{cast_from_cast_list: true}] = performances(way)
    end

    test "an edition S4 brought in is cited, not made again", %{plays: plays} do
      massinger = entry_fixture("T04:116")

      run("playcode.import.performances", ["--path", @performances])

      assert Enum.any?(performances(plays["0309"]), &(&1.source_entry_id == massinger.id))
      assert Bibliography.list_links(plays["0309"].id) == []
    end

    test "a company, an actor, a place and an entry Playcode already has are used, not made again",
         %{plays: plays, alchemist: alchemist} do
      # as written by hand: another case, and Wiggins's catalogue as the project cites it
      {:ok, company} = Performances.find_or_create_company("THE KING’S MEN")
      naples = place_fixture(%{"name" => "Nápoles"})

      {:ok, _burbage} =
        Performances.find_or_create_actor(%{"surname" => "Burbage", "forename" => "Richard"})

      wiggins =
        catalogue_fixture(%{
          "pub_type" => "book",
          "monogr_author" => "Wiggins, Martin, in association with Catherine Richardson",
          "monogr_title" => "British Drama 1533–1642: A Catalogue",
          "pub_place" => "Oxford",
          "publisher" => "Oxford University Press",
          "year_text" => "2012–"
        })

      companies = length(Performances.list_companies())
      actors = length(Performances.list_actors())
      places = length(Places.list_places())

      out = run("playcode.import.performances", ["--path", @performances])

      assert [_, new_companies, new_actors, new_places] =
               Regex.run(~r/(\d+) companies, (\d+) actors, \d+ entries and (\d+) places/, out)

      assert String.to_integer(new_places) == length(Places.list_places()) - places
      assert Enum.any?(performances(plays["0671"]), &(&1.place_id == naples.id))

      assert String.to_integer(new_companies) == length(Performances.list_companies()) - companies
      assert String.to_integer(new_actors) == length(Performances.list_actors()) - actors

      assert [_one] = Enum.filter(Performances.list_companies(), &(&1.name =~ ~r/king’s men/i))
      assert Performances.get_company(company.id).name == "THE KING’S MEN"
      assert [_one] = Enum.filter(Performances.list_actors(), &(&1.surname == "Burbage"))

      assert %{sources: [{1, cited}]} = performance_lines(alchemist)
      assert cited.id == wiggins.id
      assert [_one] = Bibliography.search_entries("British Drama", nil, 10, kinds: :all)
    end

    # A work's entry is found again by the record it was made from (`filemaker_id`), not only
    # by what it says: a curator corrects it between two runs, and a play held later cites it.
    defp run_twice_citing_one_entry(later, work_title, corrected_title) do
      {:ok, archived} = Catalogue.delete_play(later)

      run("playcode.import.performances", ["--path", @performances])
      assert [entry] = Bibliography.search_entries(work_title, nil, 10, kinds: :all)
      {:ok, _} = Bibliography.update_entry(entry, %{"monogr_title" => corrected_title})

      {:ok, _} = Catalogue.restore_play(archived)
      out = run("playcode.import.performances", ["--path", @performances])

      assert out =~ ~r/created \d+ performances, \d+ companies, \d+ actors, 0 entries/
      assert length(Bibliography.search_entries(work_title, nil, 10, kinds: :all)) == 1
      assert Enum.any?(performances(later), &(&1.source_entry_id == entry.id))
    end

    test "a hand-listed work's entry is cited again by a play held later, even corrected", %{
      plays: plays
    } do
      # Wiggins's entry is T13:87, its hand list's first record; 0038 cites another, 93
      run_twice_citing_one_entry(plays["0038"], "British Drama", "British Drama 1533–1642, 2012")
    end

    test "a hand-listed work whose first record a later play cites does not stop the run", %{
      plays: plays
    } do
      # 0379 makes CATCOM's entry from record 119, 0671 cites 119 and 468
      run_twice_citing_one_entry(plays["0671"], "CATCOM", "Base de datos CATCOM, corregida")
    end

    test "a lone record's entry, corrected, is cited, not made again", %{plays: plays} do
      lone = entry_fixture("T13:102", %{"kind" => "catalogue", "monogr_title" => "Corrected"})

      run("playcode.import.performances", ["--path", @performances])

      assert Enum.any?(performances(plays["0644"]), &(&1.source_entry_id == lone.id))
    end

    test "a second run changes nothing", %{plays: plays} do
      run("playcode.import.performances", ["--path", @performances])
      count = performance_count(plays)
      leftovers = performance_leftovers()

      out = run("playcode.import.performances", ["--path", @performances])

      assert out =~ "already imported: #{map_size(plays)} plays"
      assert out =~ "created 0 performances, 0 companies, 0 actors, 0 entries and 0 places"
      assert performance_count(plays) == count
      assert performance_leftovers() == leftovers
    end

    # As S3, S4 and S9b learned: the play's filemaker performances alone are no marker, since
    # a curator may delete every one of them.
    test "performances a curator deleted stay deleted", %{alchemist: alchemist} do
      run("playcode.import.performances", ["--path", @performances])

      for p <- performances(alchemist), do: {:ok, _} = Performances.delete_performance(p)

      run("playcode.import.performances", ["--path", @performances])

      assert performances(alchemist) == []
    end

    test "a play's own performances stay, FileMaker's go after them", %{alchemist: alchemist} do
      own = performance_fixture(alchemist, %{"date_text" => "1700"})

      run("playcode.import.performances", ["--path", @performances])

      assert [first | imported] = Enum.sort_by(performances(alchemist), & &1.position)
      assert {first.id, first.position, first.origin} == {own.id, 0, "manual"}
      assert Enum.all?(imported, &(&1.origin == "filemaker"))
      assert Enum.map(imported, & &1.position) == Enum.to_list(1..length(imported))
    end

    # The Way of the World's cast-list switch is unique per play: a curator who set it on a
    # performance of their own makes FileMaker's 1700 performance refuse, and then nothing
    # of the run stays, not the performances before it, not the companies, places or entries.
    test "a write the database refuses rolls the whole run back, naming the performance", %{
      plays: plays,
      way: way
    } do
      own = performance_fixture(way, %{"cast_from_cast_list" => true})

      error =
        assert_raise Mix.Error, fn ->
          Mix.Task.rerun("playcode.import.performances", ["--path", @performances])
        end

      assert error.message =~ "performance T11:145"
      assert error.message =~ "is already set on another performance of this play"

      assert Enum.map(performances(way), & &1.id) == [own.id]
      assert performance_count(Map.delete(plays, "0313")) == 0

      assert %{companies: [], actors: [], places: [], entries: [], log: []} =
               performance_leftovers()
    end

    test "a missing dump is refused" do
      assert_raise Mix.Error, ~r/cannot read/, fn ->
        Mix.Task.rerun("playcode.import.performances", [
          "--path",
          "test/fixtures/filemaker/nope"
        ])
      end
    end
  end
end
