defmodule Playcode.Import.WitnessesTest do
  @moduledoc """
  What the witness import would write, from a sample of FileMaker's T03 with one record per
  rule (test/fixtures/filemaker/witnesses/regenerate.exs). The writing itself is tested
  through the mix task, in test/mix/tasks_test.exs.
  """
  use Playcode.DataCase, async: true

  import Playcode.TestFixtures

  alias Playcode.Import.Witnesses, as: Import
  alias Playcode.Witnesses

  @dump "test/fixtures/filemaker/witnesses"

  setup do
    plays =
      for {code, author} <- [
            {"EMOTHE0010_Hamlet", "William Shakespeare"},
            {"EMOTHE0020_Empty", "Author"},
            {"EMOTHE0153_RomeoAndJuliet", "William Shakespeare"},
            {"EMOTHE0163_Orbecca", "Giovan Battista Giraldi Cinthio"},
            {"EMOTHE0231_Sofonisba", "Giovan Giorgio Trissino"},
            {"EMOTHE0389_ElCondeDeSex", "Antonio Coello"},
            {"EMOTHE0435_ElBastardoMudarra", "Félix Lope de Vega y Carpio"},
            {"EMOTHE0479_Cleopatre", "Étienne Jodelle"},
            {"EMOTHE0530_Pyrame", "Théophile de Viau"}
          ],
          into: %{},
          do: {code, play_fixture(%{"code" => code, "author_name" => author})}

    {:ok, data} = Import.load(@dump)
    %{plays: plays, data: data}
  end

  defp plan(%{plays: plays, data: data}), do: Import.plan(data, Map.values(plays))
  defp on(plan, code), do: for(w <- plan.witnesses, w.code == code, do: w)

  test "a test record and an empty one are skipped by id, whatever play they name", ctx do
    plan = plan(ctx)

    assert plan.skipped == %{test_record: ["T03:32"], empty: ["T03:15"]}
    assert plan.not_held == 1
    assert on(plan, "EMOTHE0020_Empty") == []
  end

  test "each field lands in its column, in FileMaker's order", ctx do
    assert [q1, f1] = on(plan(ctx), "EMOTHE0010_Hamlet")

    assert %{
             filemaker_id: "T03:33",
             siglum: "Q1",
             title: "THE Tragicall Historie of HAMLET Prince of Denmarke.",
             normalized_title: "The Tragical History of Hamlet, Prince of Denmark",
             attribution: "Shakespeare, William",
             pub_place: "London",
             publisher: "Ling, Nicholas; Trundell, John",
             date: "1603",
             format: "4º",
             witness_type: "loose",
             shelfmark: nil,
             note:
               "Usual abbreviation: Q1. Often referred to as “bad quarto”. Printer: Simmes, Valentine"
           } = q1

    assert %{filemaker_id: "T03:36", siglum: "F1"} = f1

    assert [%{shelfmark: "BN 16630"}] =
             for(
               w <- on(plan(ctx), "EMOTHE0389_ElCondeDeSex"),
               w.filemaker_id == "T03:268",
               do: w
             )
  end

  test "the type is the deepest level FileMaker set, its 'no consta' the parent", ctx do
    assert Map.new(plan(ctx).witnesses, &{&1.filemaker_id, &1.witness_type}) == %{
             "T03:33" => "loose",
             "T03:36" => "collection_single_author",
             "T03:77" => "collection_single_author",
             "T03:79" => "autograph",
             "T03:92" => "collection_single_author",
             "T03:140" => "loose",
             "T03:142" => "collection",
             "T03:143" => "loose",
             "T03:240" => "early_edition",
             "T03:267" => "collection_several_authors",
             "T03:268" => "manuscript",
             "T03:269" => "copy",
             "T03:499" => "early_edition"
           }
  end

  test "Jodelle's name is dropped from a Spanish play's witnesses and kept on his own", ctx do
    plan = plan(ctx)

    assert plan.dropped == [
             "T03:77 on EMOTHE0435_ElBastardoMudarra",
             "T03:79 on EMOTHE0435_ElBastardoMudarra"
           ]

    assert Enum.map(on(plan, "EMOTHE0435_ElBastardoMudarra"), & &1.attribution) == [nil, nil]
    assert [%{attribution: "Jodelle, Étienne"}] = on(plan, "EMOTHE0479_Cleopatre")
  end

  test "a siglum the play already has is skipped", ctx do
    {:ok, _} =
      Witnesses.create_witness(%{
        play_id: ctx.plays["EMOTHE0010_Hamlet"].id,
        siglum: "F1",
        title: "Typed by hand"
      })

    plan = plan(ctx)

    assert plan.skipped.siglum_taken == ["T03:36 on EMOTHE0010_Hamlet"]
    assert [%{siglum: "Q1"}] = on(plan, "EMOTHE0010_Hamlet")
  end
end
