defmodule Playcode.WitnessesTest do
  @moduledoc """
  A play's witnesses through `Playcode.Witnesses`: order, validation, scoping, and the sigla
  a TEI import must leave alone. Spec: docs/superpowers/specs/2026-10-10-s3-witnesses-design.md.
  """
  use Playcode.DataCase, async: true

  import Playcode.TestFixtures

  alias Playcode.Witnesses

  defp witness!(play, attrs) do
    {:ok, witness} = Witnesses.create_witness(Map.put(attrs, "play_id", play.id))
    witness
  end

  defp sigla(play), do: play.id |> Witnesses.list_for_play() |> Enum.map(& &1.siglum)

  describe "a play's witnesses" do
    test "a new witness goes last, whatever position it is given" do
      play = play_fixture()
      witness!(play, %{"siglum" => "Q1", "title" => "Uno"})
      witness!(play, %{"siglum" => "Q2", "title" => "Dos", "position" => 0})

      assert sigla(play) == ["Q1", "Q2"]
    end

    test "moving swaps a witness with its neighbour; past either end nothing moves" do
      play = play_fixture()
      [q1, q2, q3] = for s <- ~w(Q1 Q2 Q3), do: witness!(play, %{"siglum" => s, "title" => s})

      assert :ok = Witnesses.move_witness(q3, :up)
      assert sigla(play) == ["Q1", "Q3", "Q2"]

      assert :ok = Witnesses.move_witness(q1, :up)
      assert :ok = Witnesses.move_witness(q2, :down)
      assert sigla(play) == ["Q1", "Q3", "Q2"]
    end

    test "a deleted witness leaves no tie behind it" do
      play = play_fixture()
      [_q1, q2, _q3] = for s <- ~w(Q1 Q2 Q3), do: witness!(play, %{"siglum" => s, "title" => s})
      {:ok, _} = Witnesses.delete_witness(q2)
      witness!(play, %{"siglum" => "Q4", "title" => "Q4"})

      assert sigla(play) == ["Q1", "Q3", "Q4"]
    end

    test "a witness needs a title, a normalised title or a note" do
      play = play_fixture()

      assert {:error, changeset} =
               Witnesses.create_witness(%{
                 "play_id" => play.id,
                 "siglum" => "Q1",
                 "format" => "4º"
               })

      assert "needs a title, a normalised title or a note" in errors_on(changeset).title

      for field <- ~w(title normalized_title note) do
        assert {:ok, _} = Witnesses.create_witness(%{"play_id" => play.id, field => "Algo"})
      end
    end

    test "a siglum is the play's own: unique within it, free in another" do
      play = play_fixture()
      witness!(play, %{"siglum" => "Q1", "title" => "Uno"})

      assert {:error, changeset} =
               Witnesses.create_witness(%{
                 "play_id" => play.id,
                 "siglum" => "Q1",
                 "title" => "Otro"
               })

      assert "is already used by another witness of this play" in errors_on(changeset).siglum

      assert {:ok, _} =
               Witnesses.create_witness(%{
                 "play_id" => play_fixture().id,
                 "siglum" => "Q1",
                 "title" => "Otro"
               })
    end

    test "a witness id from the browser resolves only to this play's" do
      play = play_fixture()
      mine = witness!(play, %{"title" => "Mío"})
      theirs = witness!(play_fixture(), %{"title" => "Ajeno"})

      assert Witnesses.get_witness(play.id, mine.id).id == mine.id

      for id <- [theirs.id, Ecto.UUID.generate(), "not-an-id"] do
        assert Witnesses.get_witness(play.id, id) == nil, inspect(id)
      end
    end

    test "the sigla a TEI import must leave alone: the play's witnesses' and its editions'" do
      play = play_fixture()
      witness!(play, %{"siglum" => "Q1", "title" => "Uno"})
      witness!(play, %{"title" => "Sin sigla"})

      bibliography_fixture(play, %{
        "kind" => "modern_edition",
        "monogr_title" => "Chief Pre-Shakespearean Dramas",
        "siglum" => "ADA"
      })

      bibliography_fixture(play_fixture(), %{
        "kind" => "modern_edition",
        "monogr_title" => "Medieval Drama",
        "siglum" => "BEV"
      })

      assert Witnesses.taken_sigla(play.id) == MapSet.new(["Q1", "ADA"])
    end

    test "the play's pages read its witnesses in order" do
      play = play_fixture()
      for s <- ~w(Q2 Q1), do: witness!(play, %{"siglum" => s, "title" => s})

      assert play.id
             |> Playcode.Catalogue.get_play_with_all!()
             |> Map.fetch!(:witnesses)
             |> Enum.map(& &1.siglum) ==
               ["Q2", "Q1"]
    end
  end

  describe "the printed line" do
    alias Playcode.Witnesses.Witness

    test "every field, in emothe.uv.es's order" do
      witness = %Witness{
        title: "THE Tragicall Historie of HAMLET Prince of Denmarke.",
        normalized_title: "The Tragical History of Hamlet, Prince of Denmark",
        attribution: "Shakespeare, William",
        pub_place: "London",
        publisher: "Ling, Nicholas; Trundell, John",
        date: "1603",
        format: "4º",
        note: "Printer: Simmes, Valentine",
        shelfmark: "C.34.k.1"
      }

      assert Witnesses.plain(witness) ==
               "THE Tragicall Historie of HAMLET Prince of Denmarke. " <>
                 "[The Tragical History of Hamlet, Prince of Denmark]. Shakespeare, William. " <>
                 "London. Ling, Nicholas; Trundell, John. 1603. 4º. " <>
                 "Printer: Simmes, Valentine. Archivo: C.34.k.1."
    end

    test "an empty field drops out with its full stop, and one ending in a stop gets no second" do
      assert Witnesses.plain(%Witness{title: "El conde de Sex", shelfmark: "16722"}) ==
               "El conde de Sex. Archivo: 16722."

      assert Witnesses.plain(%Witness{
               normalized_title: "Ralph Roister Doister",
               date: "1566 ?",
               note: "[1566 ?] No title page."
             }) == "[Ralph Roister Doister]. 1566 ? [1566 ?] No title page."
    end

    test "line breaks and doubled spaces collapse, the whole title is italic, the rest escaped" do
      witness = %Witness{
        title: "Oeuvres <<et>> meslanges,  &\nLimodin\n",
        note: "edición de Charles de la\nMothe\n"
      }

      assert Witnesses.plain(witness) ==
               "Oeuvres et meslanges, & Limodin. edición de Charles de la Mothe."

      assert witness |> Witnesses.html() |> Phoenix.HTML.safe_to_string() ==
               "<em>Oeuvres et meslanges, &amp; Limodin</em>. edición de Charles de la Mothe."
    end
  end

  describe "in TEI" do
    alias Playcode.Witnesses.Witness

    test "the xml:id is the siglum when XML allows it, prefixed and cleaned when not" do
      for {siglum, id} <- [
            {"Q1", "Q1"},
            {"Aut.", "Aut."},
            {"PXXIV", "PXXIV"},
            {"1623b", "wit-1623b"},
            {"Q 1", "wit-Q_1"},
            {nil, nil}
          ] do
        assert Witnesses.xml_id(%Witness{siglum: siglum}) == id, inspect(siglum)
      end
    end

    test "every type has its TEI pair, and the pair names the type back" do
      for type <- Witness.types() do
        {tei_type, subtype} = Witnesses.tei_type(type)
        assert Witnesses.type_from_tei(tei_type, subtype) == type
      end

      assert Witnesses.tei_type(nil) == nil
      assert Witnesses.type_from_tei("libro", nil) == nil
    end
  end
end
