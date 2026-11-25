defmodule Playcode.CatalogueTest do
  use Playcode.DataCase, async: true

  import Playcode.TestFixtures

  alias Playcode.Catalogue
  alias Playcode.Catalogue.Play
  alias Playcode.PlayContent

  describe "a play's verse count" do
    import Playcode.ImportHelpers

    # Q10: statistics count the structure; a number is only a location label. An S play
    # numbers only a speech's first line, so counting numbers counted speeches.
    test "counts every verse once, by its first piece, numbered or not" do
      header =
        ~s(<refsDecl n="manual"><citeStructure unit="speech" match="/TEI/text/body//sp" use="@n"/></refsDecl>)

      play =
        import_tei!(
          tei(
            encoding_desc: header,
            body: """
            <div1 type="acto" n="1"><head>Acto I</head>
              <sp><speaker>ANA</speaker><l n="1">a</l><l>b</l><l part="I">c</l></sp>
              <sp><speaker>BLAS</speaker><l part="F" n="2">y c</l><l>d</l></sp>
            </div1>
            """
          )
        )

      Playcode.PlayContent.refresh_derived(play.id)

      assert Catalogue.get_play!(play.id).verse_count == 4
    end
  end

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

    test "a code holds letters, digits and underscores only, as a TEI file's code is read" do
      assert {:error, changeset} =
               Catalogue.create_play(%{"code" => "EMOTHE9102_East-WardHoe", "title" => "x"})

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
      # FileMaker's EMOTHE0797, "A Maior Glória de Portugal e Afronta Maior de Castela…"
      {"a title of 405 characters", %{"title" => String.duplicate("Glória ", 58)}, nil},
      {"a sort title of 405 characters", %{"title_sort" => String.duplicate("Glória ", 58)}, nil},
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

  # A code is its library, the play's number there (FileMaker's title id for EMOTHE) and a
  # readable name; Postgres writes it from the three.
  describe "a play's code" do
    defp create(attrs), do: Catalogue.create_play(Map.put(attrs, "title", "Prueba"))

    test "is its library, its number at four digits or more, and its name" do
      for {attrs, code} <- [
            {%{"library" => "TEST", "number" => "7", "slug" => "Prueba"}, "TEST0007_Prueba"},
            {%{"library" => "TEST", "number" => "12345", "slug" => "Larga"}, "TEST12345_Larga"},
            {%{"library" => "TEST", "number" => "8"}, "TEST0008"}
          ] do
        assert {:ok, play} = create(attrs)
        assert play.code == code
        assert Catalogue.get_play_by_code!(code).id == play.id
      end
    end

    test "given whole, is taken apart into its library, number and name" do
      {:ok, play} = create(%{"code" => "TEST0009_Entera"})

      assert {play.library, play.number, play.slug} == {"TEST", 9, "Entera"}
    end

    test "names one play per number in a library" do
      n = System.unique_integer([:positive])
      {:ok, _} = create(%{"library" => "TEST", "number" => "#{n}", "slug" => "Una"})

      assert {:error, changeset} =
               create(%{"library" => "TEST", "number" => "#{n}", "slug" => "Otra"})

      assert errors_on(changeset)[:number] == ["has already been taken"]
      assert {:ok, _} = create(%{"library" => "AL", "number" => "#{n}", "slug" => "Otra"})
    end

    test "that is no library and number is refused" do
      for code <- ["PLAY123", "EMOTHE 9999", "CTCE0387", "EMOTHE_Sin", "EMOTHE0001_Con-guion"] do
        assert {:error, changeset} = create(%{"code" => code})
        assert Map.has_key?(errors_on(changeset), :code), code
      end
    end

    # Past the changeset on purpose: the site turns codes into folder names it deletes
    # and rewrites, and the database is what holds every row, however it was written.
    test "that is not a plain name cannot be stored at all" do
      import Ecto.Query
      alias Playcode.Repo
      play = play_fixture()

      for parts <- [[slug: "../../etc"], [slug: "a/b"], [library: "X"], [number: 0]] do
        assert_raise Postgrex.Error, ~r/check_violation/, fn ->
          Repo.update_all(where(Play, id: ^play.id), set: parts)
        end
      end
    end

    test "of the TEST library is never published" do
      assert {:error, changeset} = create(%{"code" => "TEST0010", "is_complete" => "true"})
      assert Map.has_key?(errors_on(changeset), :is_complete)
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

  describe "a play's text" do
    test "a play made with nothing in it has no text, and no form" do
      {:ok, play} =
        Catalogue.create_play(%{
          "title" => "Sin texto",
          "code" => unique_code(),
          "language" => "es"
        })

      refute Play.has_text?(play)
      assert Play.form(play) == nil
      assert play.verse_count == nil
    end

    test "its first line gives it a text, and deleting its last takes it away" do
      play = play_without_text_fixture()

      {:ok, act} =
        PlayContent.create_division(%{play_id: play.id, type: "acto", number: 1, position: 1})

      refute Play.has_text?(Catalogue.get_play!(play.id))

      {:ok, _stage} =
        PlayContent.create_element(%{
          play_id: play.id,
          division_id: act.id,
          type: "stage_direction",
          content: "Sale.",
          position: 1
        })

      refute Play.has_text?(Catalogue.get_play!(play.id))

      {:ok, line} =
        PlayContent.create_element(%{
          play_id: play.id,
          division_id: act.id,
          type: "prose",
          content: "",
          position: 2
        })

      assert Play.has_text?(Catalogue.get_play!(play.id))
      assert Play.form(Catalogue.get_play!(play.id)) == "prose"

      {:ok, _} = PlayContent.delete_element(line)
      refute Play.has_text?(Catalogue.get_play!(play.id))
      assert Catalogue.get_play!(play.id).verse_count == nil
    end

    test "the play list's no-text filter finds it" do
      without = play_without_text_fixture()
      with_text = play_fixture()
      codes = Catalogue.list_plays(status: :no_text) |> Enum.map(& &1.code)
      assert without.code in codes
      refute with_text.code in codes
    end
  end
end
