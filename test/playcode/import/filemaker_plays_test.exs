defmodule Playcode.Import.FilemakerPlaysTest do
  @moduledoc "Which of FileMaker's records become plays, and with what."
  use Playcode.DataCase, async: true

  import Playcode.ImportHelpers
  import Playcode.TestFixtures

  alias Playcode.Catalogue
  alias Playcode.Import.FilemakerPlays

  @dir "test/fixtures/filemaker/plays"

  defp plan(plays) do
    {:ok, data} = FilemakerPlays.load(@dir)
    FilemakerPlays.plan(data, plays)
  end

  defp held do
    [
      play_fixture(%{"code" => "EMOTHE0201_ElBurladorDeSevilla"}),
      play_fixture(%{"code" => "EMOTHE0283_TisPityShesAWhore"}),
      play_fixture(%{"code" => "EMOTHE0195_Macbeth"}) |> Catalogue.delete_play() |> elem(1)
    ]
  end

  test "a record whose code Playcode does not hold becomes a play, with its kind and original" do
    plan = plan(held())

    assert Enum.map(plan.create, & &1.attrs["code"]) ==
             ~w(EMOTHE0110_Hamlet1603 EMOTHE0401_Mucedorus EMOTHE0439 EMOTHE0596)

    abuseur = List.last(plan.create)

    assert abuseur.attrs == %{
             "code" => "EMOTHE0596",
             "title" => "L’abuseur de Séville",
             "title_sort" => "abuseur de Séville, L’",
             "author_sort" => "Molina, Tirso de",
             "author_name" => "Tirso de Molina",
             "language" => "fr",
             "relationship_type" => "traduccion",
             "historical_time" => "siglo_xvii",
             "historical_time_note" => "Sevilla, hacia 1350",
             "composition_date_note" => "1616; hacia 1630"
           }

    assert abuseur.original == "EMOTHE0201"
    assert abuseur.state == "sin texto"
  end

  test "a code Playcode holds is left alone, archived or not, whatever its tail" do
    plan = plan(held())
    assert plan.held == 2
    refute Enum.any?(plan.create, &(&1.attrs["code"] =~ ~r/EMOTHE0(195|201)/))
  end

  test "a record named after a file Playcode holds under another code is a clash, skipped" do
    assert %{code: "EMOTHE0627", title: "Tis Pity She’s a Whore", reason: :held_under_file_name} in plan(
             held()
           ).skipped
  end

  test "tests, records without a title, a work or a language are skipped and named" do
    skipped = plan([]).skipped |> Map.new(&{&1.code, &1.reason})

    assert skipped == %{
             "EMOTHE0203" => :test,
             "EMOTHE0376" => :test,
             "EMOTHE0650" => :no_title,
             "EMOTHE0795" => :no_title,
             "EMOTHE0748" => :no_work,
             "EMOTHE0513" => :no_language
           }
  end

  test "FileMaker's file name is the code when it is one, an HIE file's as EMOTHE" do
    codes = plan([]).create |> Enum.map(& &1.attrs["code"])
    assert "EMOTHE0401_Mucedorus" in codes
    # Cleaned as the TEI import cleans a file's code; it used to fall back to the record's
    # number, which a TEI file named after it could never update (EMOTHE0110 on 2026-11-17)
    assert "EMOTHE0110_Hamlet1603" in codes
  end

  test "a play created from a record is the one its TEI file updates" do
    {:ok, created} = FilemakerPlays.apply_plan(plan([]))

    play =
      import_tei!(
        tei(
          code: "EMOTHE0110_Hamlet(1603)",
          body: ~s(<div1 type="acto" n="1"><sp><speaker>A</speaker><l n="1">Uno.</l></sp></div1>)
        )
      )

    assert play.code == "EMOTHE0110_Hamlet1603"
    assert length(Catalogue.list_plays()) == created
  end

  test "a record's original is its work's main record, held and not archived, or created" do
    created = plan([]).create |> Map.new(&{&1.attrs["code"], &1})
    held = plan(held()).create |> Map.new(&{&1.attrs["code"], &1})

    assert created["EMOTHE0596"].original == "EMOTHE0201"
    assert created["EMOTHE0401_Mucedorus"].original == "EMOTHE0195"
    assert held["EMOTHE0439"].original == "EMOTHE0201"
    # EMOTHE0195 is archived
    assert held["EMOTHE0401_Mucedorus"].original == nil
    # an original names none, even when FileMaker's work has another main record
    assert created["EMOTHE0110_Hamlet1603"].original == nil
    assert created["EMOTHE0201_ElBurladorDeSevilla"].original == nil

    assert created["EMOTHE0439"].attrs["relationship_type"] == "adaptacion"
    assert created["EMOTHE0401_Mucedorus"].attrs["relationship_type"] == "version"
    refute Map.has_key?(created["EMOTHE0110_Hamlet1603"].attrs, "relationship_type")
  end

  test "an author is turned at its first comma; a lone name stays as it is" do
    authors = plan([]).create |> Map.new(&{&1.attrs["code"], &1.attrs["author_name"]})
    assert authors["EMOTHE0439"] == "Molière"
    assert authors["EMOTHE0401_Mucedorus"] == "[Anonymous]"
  end
end
