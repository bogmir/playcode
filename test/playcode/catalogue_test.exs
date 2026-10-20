defmodule Playcode.CatalogueTest do
  use Playcode.DataCase, async: true

  import Playcode.TestFixtures

  alias Playcode.Catalogue

  describe "finding plays" do
    test "search matches title, author and code" do
      play = play_fixture(%{"title" => "Comedia nueva", "author_name" => "Lope"})
      _other = play_fixture(%{"title" => "Otra obra", "author_name" => "Calderón"})

      for term <- ["Comedia", "Lope", play.code] do
        assert Enum.map(Catalogue.list_plays(search: term), & &1.id) == [play.id], term
      end
    end
  end

  describe "archiving" do
    test "an archived play disappears from every read, and its code stays reserved" do
      play = play_fixture(%{"code" => "EMOTHE9101_Archived"})

      assert {:ok, archived} = Catalogue.delete_play(play)
      assert archived.deleted_at

      assert Catalogue.list_plays() == []
      assert Catalogue.count_plays() == 0
      assert_raise Ecto.NoResultsError, fn -> Catalogue.get_play!(play.id) end
      assert_raise Ecto.NoResultsError, fn -> Catalogue.get_play_by_code!(play.code) end

      assert Enum.map(Catalogue.list_plays(include_deleted: true), & &1.id) == [play.id]
      assert Catalogue.get_play!(play.id, include_deleted: true).id == play.id

      assert {:error, changeset} = Catalogue.create_play(%{"code" => play.code, "title" => "x"})
      assert %{code: _} = errors_on(changeset)
    end

    test "restoring brings it back" do
      {:ok, archived} = Catalogue.delete_play(play_fixture())

      assert {:ok, restored} = Catalogue.restore_play(archived)
      refute restored.deleted_at
      assert Enum.map(Catalogue.list_plays(), & &1.id) == [archived.id]
    end

    # The destructive path, deliberately wired to no button (see CLAUDE.md).
    test "purging destroys it" do
      play = play_fixture()

      assert {:ok, _} = Catalogue.purge_play(play)
      assert Catalogue.list_plays(include_deleted: true) == []
    end
  end

  describe "what a play may hold" do
    # {what, attributes, the field it is refused on (nil = accepted)}
    @rules [
      {"no title", %{"title" => nil}, :title},
      {"a historical time outside the vocabulary", %{"historical_time" => "siglo_xxi"},
       :historical_time},
      {"a composition year range",
       %{"composition_date_from" => "1606", "composition_date_to" => "1607"}, nil},
      {"a single composition year",
       %{"composition_date_from" => "1614", "composition_date_to" => "1614"}, nil},
      {"a dating note with no years", %{"composition_date_note" => "alrededor de 1601"}, nil},
      {"a lone start year", %{"composition_date_from" => "1606"}, :composition_date_from},
      {"a lone end year", %{"composition_date_to" => "1607"}, :composition_date_to},
      {"an end year before the start year",
       %{"composition_date_from" => "1607", "composition_date_to" => "1606"},
       :composition_date_to},
      {"a year outside the plausible range",
       %{"composition_date_from" => "160", "composition_date_to" => "160"},
       :composition_date_from}
    ]

    for {what, attrs, refused_on} <- @rules do
      @attrs attrs
      @refused_on refused_on

      test "#{what} is #{if refused_on, do: "refused", else: "accepted"}" do
        result =
          Catalogue.create_play(
            Map.merge(%{"title" => "A Play", "code" => unique_code()}, @attrs)
          )

        case @refused_on do
          nil ->
            assert {:ok, _} = result

          field ->
            assert {:error, changeset} = result
            assert Map.has_key?(errors_on(changeset), field)
        end
      end
    end
  end

  describe "what a paratext may hold" do
    # The kind is written to the file as a div's @type, a TEI token (teidata.enumerated):
    # any one word is kept, a kind of the file's own included; spaces are refused.
    test "a kind is one word, known or not" do
      play = play_fixture()

      assert {:ok, %{kind: "carta_al_lector"}} =
               Catalogue.create_paratext(%{
                 play_id: play.id,
                 kind: "carta_al_lector",
                 content: "Lector."
               })

      assert {:error, changeset} =
               Catalogue.create_paratext(%{
                 play_id: play.id,
                 kind: "two words",
                 content: "Lector."
               })

      assert Map.has_key?(errors_on(changeset), :kind)
    end

    # The scene of the action is the front's <set>, which TEI gives no <trailer>.
    test "the scene of the action has no closing formula" do
      play = play_fixture()

      assert {:error, changeset} =
               Catalogue.create_paratext(%{
                 play_id: play.id,
                 kind: "lugar_accion",
                 content: "Un bosque.",
                 trailer: "FIN"
               })

      assert Map.has_key?(errors_on(changeset), :trailer)
    end

    # A heading alone has no lines, and its file no stanzas to say it is in verse.
    test "a heading alone is not in verse" do
      play = play_fixture()

      assert {:ok, %{verse: false}} =
               Catalogue.create_paratext(%{
                 play_id: play.id,
                 kind: "head_title",
                 heading: "LOS CONTENTOS",
                 verse: true
               })
    end
  end
end
