defmodule Playcode.Import.BibliographyTest do
  @moduledoc """
  What the bibliography import would write, from a six-table dump cut down to one case per
  rule. The writing itself is tested through the mix task, in test/mix/tasks_test.exs.
  """
  use Playcode.DataCase, async: true

  import Playcode.TestFixtures

  alias Playcode.Import.Bibliography

  @dump "test/fixtures/filemaker/ctce_dades"

  setup do
    hamlet = play_fixture(%{"code" => "EMOTHE0010_Hamlet"})
    antony = play_fixture(%{"code" => "EMOTHE0038_AntonyAndCleopatra"})
    {:ok, data} = Bibliography.load(@dump)

    %{plan: Bibliography.plan(data, [hamlet, antony]), hamlet: hamlet, antony: antony}
  end

  test "every skip is listed under its reason", %{plan: plan} do
    assert plan.skipped == %{
             no_record: ["T12 link to version 38", "T04 link to version 10"],
             missing_record: ["T12:99", "T04:777"],
             no_name: ["T12:5", "T04:44"],
             test_record: ["T04:9"],
             duplicate_link: ["T12:1 on EMOTHE0038_AntonyAndCleopatra"],
             unlinked: ["T12:7"]
           }

    assert plan.not_held == 1
  end

  test "a record shared by two plays is one entry with two links", %{plan: plan} do
    assert plan.entries |> Map.keys() |> Enum.sort() ==
             ~w(T04:40 T04:52 T04:576 T12:1 T12:2 T12:3 T12:4 T12:6)

    assert length(plan.links) == 10
    assert Enum.count(plan.links, &(&1.filemaker_id == "T12:4")) == 2
    assert plan.existing == []
  end

  test "an uncategorised record is criticism, and city and publisher come from T13", %{
    plan: plan
  } do
    assert %{kind: "criticism", pub_place: "Madrid", publisher: "Iberoamericana"} =
             plan.entries["T12:2"]

    assert plan.entries["T12:2"].analytic_title == "Lope y su fábula de <<Adonis y Venus>>"
  end

  test "a book's first title is its series", %{plan: plan} do
    assert %{
             kind: "translation",
             pub_type: "book",
             language: "de",
             analytic_title: nil,
             series: "Das Bühnenspiel",
             monogr_title: "Altweibermär",
             original_title: "Old Wife's Tale"
           } = plan.entries["T12:3"]
  end

  test "a publisher key that is not a number is the publisher's name", %{plan: plan} do
    assert plan.entries["T12:6"].publisher == "B.R. Grüner Publishing Company"
  end

  test "the record's note stays internal; the link's note is the link's", %{
    plan: plan,
    antony: antony
  } do
    assert plan.entries["T12:1"].note == "Sobre Tasso"
    link = Enum.find(plan.links, &(&1.play_id == antony.id and &1.filemaker_id == "T12:1"))
    assert link.note =~ "10.2307/3190039"
  end

  test "a chapter edition has two levels, and VolTomo is its number of volumes", %{plan: plan} do
    assert %{
             pub_type: "book_section",
             analytic_editors: "Rowe, Nicholas",
             analytic_title: "Hamlet",
             monogr_title: "The Works of Mr. William Shakespeare",
             volumes_total: "6",
             volume: nil
           } = plan.entries["T04:52"]
  end

  test "a book edition's second title is its series, and its note is printed", %{plan: plan} do
    assert %{
             pub_type: "book",
             monogr_editors: "Thompson, Ann; Taylor, Neil",
             monogr_title: "Hamlet",
             series: "The Arden Shakespeare",
             public_note: "Third series",
             siglum: "ARD3Q2",
             note: nil
           } = plan.entries["T04:40"]
  end

  test "a duplicated edition id uses the copy that names something", %{plan: plan} do
    assert plan.entries["T04:576"].monogr_title == "Antony and Cleopatra"
  end

  test "each play's link carries its own volume and pages", %{
    plan: plan,
    hamlet: hamlet,
    antony: antony
  } do
    link = fn play ->
      Enum.find(plan.links, &(&1.play_id == play.id and &1.filemaker_id == "T04:52"))
    end

    assert %{volume: "5", pages: "2366-2466"} = link.(hamlet)
    assert %{volume: "7", pages: "100-200"} = link.(antony)
  end

  # T04:34 is Frenk Alatorre's Comedias (1982), a real edition: only its siglum, "TES2", is
  # FileMaker test data (docs/superpowers/specs/2026-10-10-s3-witnesses-design.md).
  test "FileMaker's test siglum on a real edition is dropped, and a real one is kept" do
    no_lookups = %{cities: %{}, publishers: %{}}

    row = %{
      "_kp_IdEdicionModerna" => "34",
      "EdiMod_Titulo" => "Comedias",
      "EdiMod_Siglas" => "TES2"
    }

    assert %{siglum: nil, monogr_title: "Comedias"} = Bibliography.edition_attrs(row, no_lookups)

    assert %{siglum: "RSC"} =
             Bibliography.edition_attrs(%{row | "EdiMod_Siglas" => "RSC"}, no_lookups)
  end
end
