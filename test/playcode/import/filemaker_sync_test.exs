defmodule Playcode.Import.FilemakerSyncTest do
  @moduledoc """
  The sync's rules, one combination per test, against the tracked FileMaker
  samples as `Filemaker.load_index/1` and `load_versions/1` read them. The mix
  task that runs it is asserted in test/mix/tasks_test.exs.
  """
  use Playcode.DataCase, async: true

  import Playcode.TestFixtures

  alias Playcode.Catalogue
  alias Playcode.Import.{Filemaker, FilemakerSync}

  # Antony and Cleopatra: EN original EMOTHE0038 + ES translation EMOTHE0052.
  defp index do
    {:ok, index} = Filemaker.load_index("test/fixtures/filemaker/index_sample.ndjson")
    index
  end

  defp versions do
    {:ok, versions} = Filemaker.load_versions("test/fixtures/filemaker/versions_sample.ndjson")
    versions
  end

  @t01_note "desde o posterior 1605 y anterior o hasta 1607; 1606"
  @historical_note "First century BC. The play dramatizes events taking place between 40 and 30 BC."

  defp play(code, attrs \\ %{}) do
    play_fixture(Map.merge(%{"code" => code, "language" => "es"}, attrs))
  end

  # The dating the index would fill, already stored: tests about another field merge
  # this in so the fill is a no-op.
  defp dated(note \\ "=1606 - =1607") do
    %{
      "composition_date_from" => 1606,
      "composition_date_to" => 1607,
      "composition_date_note" => note
    }
  end

  describe "derived fields, which the index overwrites" do
    test "an original stored as Spanish gets its real language" do
      plan = FilemakerSync.plan(index(), [play("EMOTHE0038_AntonyAndCleopatra")])

      assert [%{code: "EMOTHE0038", sets: sets}] = plan.changes
      assert sets.language == "en"
      refute Map.has_key?(sets, :parent_play_id)
    end

    test "a translation is marked and linked to its original" do
      original = play("EMOTHE0038_AntonyAndCleopatra", Map.put(dated(), "language", "en"))
      translation = play("EMOTHE0052_AntonioYCleopatra")

      plan = FilemakerSync.plan(index(), [original, translation])

      assert [%{code: "EMOTHE0052", sets: sets}] = plan.changes
      assert {sets.relationship_type, sets.parent_play_id} == {"traduccion", original.id}
      assert plan.unchanged == ["EMOTHE0038"]
    end

    test "a translation whose original is not imported is marked but not linked" do
      plan = FilemakerSync.plan(index(), [play("EMOTHE0052_AntonioYCleopatra")])

      assert [%{sets: sets}] = plan.changes
      assert sets.relationship_type == "traduccion"
      refute Map.has_key?(sets, :parent_play_id)
    end

    # It cleared an adaptation too until question 15: the file's kind wins now (below).
    test "a wrong translation on an original is cleared" do
      original =
        play("EMOTHE0038_AntonyAndCleopatra", %{
          "language" => "en",
          "relationship_type" => "traduccion"
        })

      assert [%{sets: %{relationship_type: nil}}] =
               FilemakerSync.plan(index(), [original]).changes
    end

    # Question 15: the file's kind wins; FileMaker's index knows only originals and
    # translations. The index would make it a translation of EMOTHE0038.
    test "an adaptation stays one, with the original it has" do
      original = play("EMOTHE0038_AntonyAndCleopatra", Map.put(dated(), "language", "en"))
      other = play("AL9998_OtraObra")

      adaptation =
        play("EMOTHE0052_AntonioYCleopatra", %{
          "relationship_type" => "adaptacion",
          "parent_play_id" => other.id
        })

      assert "EMOTHE0052" in FilemakerSync.plan(index(), [original, other, adaptation]).unchanged
    end

    # No source file names its original (none carries a relatedItem), so on a fresh
    # database the index's family is the only one an adaptation has.
    test "an adaptation with no original gets the one the index names" do
      original = play("EMOTHE0038_AntonyAndCleopatra", Map.put(dated(), "language", "en"))
      adaptation = play("EMOTHE0052_AntonioYCleopatra", %{"relationship_type" => "adaptacion"})

      assert [%{code: "EMOTHE0052", sets: sets}] =
               FilemakerSync.plan(index(), [original, adaptation]).changes

      assert sets == %{parent_play_id: original.id}
    end

    # The index heads a family with its first editor: it put Ford's 'Tis Pity under
    # Maeterlinck's adaptation of it, and Las mocedades del Cid under Le Cid, which
    # adapts it. Question 15 corrected both.
    test "a family question 15 corrected stays so" do
      ford = play("EMOTHE0283_TisPityShesAWhore", %{"language" => "en"})

      annabella =
        play("EMOTHE0317_Annabella", %{
          "language" => "fr",
          "relationship_type" => "adaptacion",
          "parent_play_id" => ford.id
        })

      corneille = play("EMOTHE9008_LeCid", %{"language" => "fr"})
      castro = play("EMOTHE0141_LasMocedadesDelCid")

      ford_family = [%{code: "EMOTHE0317", role: :editor}, %{code: "EMOTHE0283", role: :editor}]
      cid_family = [%{code: "EMOTHE9008", role: :editor}, %{code: "EMOTHE0141", role: :editor}]

      index =
        Map.new(
          [
            {"EMOTHE0283", "en", ford_family},
            {"EMOTHE0317", "fr", ford_family},
            {"EMOTHE9008", "fr", cid_family},
            {"EMOTHE0141", "es", cid_family}
          ],
          fn {code, lang, family} ->
            {code, %{code: code, lang: lang, role: :editor, family: family}}
          end
        )

      plan = FilemakerSync.plan(index, [ford, annabella, corneille, castro])

      assert plan.changes == []
    end

    test "a code absent from the index is reported, not failed" do
      # A code no TEI fixture uses: an async insert of a fixture's code can wait on the
      # plays.code index behind another suite's transaction.
      plan = FilemakerSync.plan(index(), [play("AL9999_NoEstaEnElIndice")])

      assert plan.missing == ["AL9999"]
      assert plan.changes == []
    end
  end

  describe "applying" do
    test "writes the changes and logs one activity entry per play" do
      original = play("EMOTHE0038_AntonyAndCleopatra")
      translation = play("EMOTHE0052_AntonioYCleopatra")

      results =
        index() |> FilemakerSync.plan([original, translation]) |> FilemakerSync.apply_plan()

      assert Enum.sort(results) == [{:ok, "EMOTHE0038"}, {:ok, "EMOTHE0052"}]
      assert Catalogue.get_play!(original.id).language == "en"

      reloaded = Catalogue.get_play!(translation.id)
      assert {reloaded.relationship_type, reloaded.parent_play_id} == {"traduccion", original.id}

      assert [entry] = Playcode.ActivityLog.list_entries(play_id: translation.id)
      assert entry.action == "update"
      assert entry.metadata["source"] == "filemaker_index"
      assert entry.changes["relationship_type"] == "traduccion"
    end

    test "a second pass changes nothing" do
      original = play("EMOTHE0038_AntonyAndCleopatra")
      translation = play("EMOTHE0052_AntonioYCleopatra")

      index()
      |> FilemakerSync.plan([original, translation], versions())
      |> FilemakerSync.apply_plan()

      reloaded = Enum.map([original, translation], &Catalogue.get_play!(&1.id))
      second = FilemakerSync.plan(index(), reloaded, versions())

      assert {second.changes, second.conflicts} == {[], []}
      assert Enum.sort(second.unchanged) == ["EMOTHE0038", "EMOTHE0052"]
    end
  end

  describe "curated fields, which are fill-only" do
    test "a blank historical time is filled" do
      original = play("EMOTHE0038_AntonyAndCleopatra", %{"language" => "en"})

      plan = FilemakerSync.plan(index(), [original], versions())

      assert [%{code: "EMOTHE0038", sets: sets}] = plan.changes

      assert {sets.historical_time, sets.historical_time_note} ==
               {"antiguedad_clasica", @historical_note}

      assert plan.conflicts == []
    end

    test "an equal value is left alone" do
      original =
        play(
          "EMOTHE0038_AntonyAndCleopatra",
          Map.merge(dated(@t01_note), %{
            "language" => "en",
            "historical_time" => "antiguedad_clasica",
            "historical_time_note" => @historical_note
          })
        )

      plan = FilemakerSync.plan(index(), [original], versions())

      assert {plan.changes, plan.conflicts, plan.unchanged} == {[], [], ["EMOTHE0038"]}
    end

    test "a value that disagrees is reported and kept; the blank note beside it is still filled" do
      original =
        play(
          "EMOTHE0038_AntonyAndCleopatra",
          Map.merge(dated(@t01_note), %{"language" => "en", "historical_time" => "edad_media"})
        )

      plan = FilemakerSync.plan(index(), [original], versions())

      assert [%{field: :historical_time, current: "edad_media", indexed: "antiguedad_clasica"}] =
               Enum.filter(plan.conflicts, &(&1.field == :historical_time))

      assert [%{sets: sets}] = plan.changes
      assert Map.keys(sets) == [:historical_time_note]

      FilemakerSync.apply_plan(plan)
      assert Catalogue.get_play!(original.id).historical_time == "edad_media"
    end

    test "nothing is blanked when the export has no record" do
      original =
        play(
          "EMOTHE0038_AntonyAndCleopatra",
          Map.merge(dated(), %{"language" => "en", "historical_time" => "edad_media"})
        )

      plan = FilemakerSync.plan(index(), [original], %{})

      assert {plan.changes, plan.conflicts} == {[], []}
    end

    test "force writes every conflicting value" do
      original =
        play("EMOTHE0038_AntonyAndCleopatra", %{
          "language" => "en",
          "historical_time" => "edad_media",
          "composition_date_from" => 1600,
          "composition_date_to" => 1601
        })

      plan = FilemakerSync.plan(index(), [original], versions())
      assert [{:ok, "EMOTHE0038"}] = FilemakerSync.apply_plan(plan, force: true)

      forced = Catalogue.get_play!(original.id)

      assert {forced.historical_time, forced.composition_date_from} ==
               {"antiguedad_clasica", 1606}
    end
  end

  describe "composition date" do
    test "blank columns are filled from the index header, with T01's note winning" do
      original = play("EMOTHE0038_AntonyAndCleopatra", %{"language" => "en"})

      assert [%{sets: sets}] = FilemakerSync.plan(index(), [original], versions()).changes
      assert {sets.composition_date_from, sets.composition_date_to} == {1606, 1607}
      assert sets.composition_date_note == @t01_note
    end

    test "the header's own text is the note when T01 has none" do
      original = play("EMOTHE0038_AntonyAndCleopatra", %{"language" => "en"})

      assert [%{sets: sets}] = FilemakerSync.plan(index(), [original], %{}).changes
      assert sets.composition_date_note == "=1606 - =1607"
    end

    test "a typed dating that disagrees is a conflict, not a write" do
      original =
        play("EMOTHE0038_AntonyAndCleopatra", %{
          "language" => "en",
          "composition_date_from" => 1600,
          "composition_date_to" => 1601
        })

      plan = FilemakerSync.plan(index(), [original], versions())

      assert Enum.any?(
               plan.conflicts,
               &(&1.field == :composition_date_from and &1.current == 1600)
             )

      assert Enum.all?(plan.changes, &(not Map.has_key?(&1.sets, :composition_date_from)))
    end
  end
end
