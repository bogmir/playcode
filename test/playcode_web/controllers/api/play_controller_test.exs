defmodule PlaycodeWeb.API.PlayControllerTest do
  @moduledoc "The public JSON API under /api/v1."
  use PlaycodeWeb.ConnCase, async: true

  import Playcode.ImportHelpers

  setup do
    play =
      import_tei!(
        tei(
          code: "API0001",
          title: "Obra de la API",
          title_stmt: "<author>Lope de Vega</author><principal>Joan Oleza Simó</principal>",
          source_desc:
            "<bibl><title>Primera parte</title><distributor>Gallica</distributor></bibl>",
          front: """
          <div type="elenco"><castList>
            <castItem><role xml:id="REY">EL REY</role><roleDesc>de Castilla</roleDesc><actor>Mr. Betterton</actor></castItem>
          </castList></div>
          """,
          body: """
          <div1 type="acto" n="1"><head>ACTO I</head>
            <sp who="#REY"><speaker>EL REY</speaker><lg type="redondilla"><l n="1">Primer verso</l></lg></sp>
            <stage>Vase</stage>
          </div1>
          """
        )
      )

    # Titled to sort before API0001, so ordering by code is observable.
    import_tei!(
      tei(code: "API0002", title: "Anterior obra", title_stmt: "<author>Calderón</author>")
    )

    # Imports are drafts, and the API serves complete plays only.
    Enum.each(Playcode.Catalogue.list_plays(), &Playcode.TestFixtures.mark_complete!/1)

    %{play: play}
  end

  test "lists plays, searchable, with a total", %{conn: conn} do
    assert %{"data" => all, "meta" => %{"total" => 2}} =
             json_response(get(conn, ~p"/api/v1/plays"), 200)

    assert Enum.map(all, & &1["code"]) |> Enum.sort() == ["API0001", "API0002"]

    assert %{"data" => [%{"code" => "API0001", "author" => "Lope de Vega", "url" => url}]} =
             json_response(get(conn, ~p"/api/v1/plays?search=Lope"), 200)

    assert url =~ "/plays/API0001"
  end

  test "sorts by code on request", %{conn: conn} do
    %{"data" => plays} = json_response(get(conn, ~p"/api/v1/plays?sort=code"), 200)
    assert Enum.map(plays, & &1["code"]) == ["API0001", "API0002"]
  end

  test "a play's metadata, editors and sources", %{conn: conn} do
    body = json_response(get(conn, ~p"/api/v1/plays/API0001"), 200)

    assert body["title"] == "Obra de la API"
    assert %{"name" => "Joan Oleza Simó", "role" => "principal"} in body["editors"]
    assert [%{"title" => "Primera parte", "distributor" => "Gallica"}] = body["sources"]
  end

  # The glossary's words (CONTEXT.md); the scene of the action is not a paratext.
  test "a play's paratexts, and its scene of the action, by their own names", %{conn: conn} do
    tei(
      code: "API0003",
      front: """
      <div type="dedicatoria"><head>Al duque</head><p>Señor.</p></div>
      <div type="introduccion_editor"><p>Esta edición.</p></div>
      <div type="elenco"><castList><castItem><role xml:id="DON">Don</role></castItem></castList></div>
      <set><p>London</p></set>
      """,
      # An act, for the colophon to stand after: `back` is where the outline puts a
      # paratext, and in a play with no text every paratext stands before it.
      body: ~s(<div1 type="acto" n="1"><head>ACTO I</head><p>Texto.</p></div1>),
      back: ~s(<div type="colofon"><p>Loado sea.<lb/>En Madrid</p></div>)
    )
    |> import_tei!()
    |> Playcode.TestFixtures.mark_complete!()

    json = json_response(get(conn, ~p"/api/v1/plays/API0003"), 200)

    assert %{
             "paratexts" => [
               %{
                 "kind" => "dedicatoria",
                 "heading" => "Al duque",
                 "back" => false,
                 "editorial" => false
               },
               %{"kind" => "introduccion_editor", "heading" => nil, "editorial" => true},
               %{"kind" => "colofon", "back" => true, "content" => "Loado sea.\nEn Madrid"}
             ],
             "scene_of_action" => [%{"heading" => nil, "content" => "London"}]
           } = json

    refute Map.has_key?(json, "editorial_notes")
  end

  # `back` is where the outline puts a paratext: after the last division of the text, as
  # one added by hand there is. A character is described as its first entry describes it.
  test "a paratext is after the text where the outline puts it, a character as it is first listed",
       %{conn: conn} do
    play = outline_xml() |> import_tei!() |> Playcode.TestFixtures.mark_complete!()

    {:ok, _colophon} =
      Playcode.Catalogue.create_paratext(%{
        play_id: play.id,
        kind: "colofon",
        heading: "COLOFÓN",
        content: "Impreso en Valencia.",
        position: 100,
        origin: "manual"
      })

    json = json_response(get(conn, ~p"/api/v1/plays/#{play.code}"), 200)

    assert %{"DEDICATORIA" => false, "LOA" => false, "EPÍLOGO" => true, "COLOFÓN" => true} =
             Map.new(json["paratexts"], &{&1["heading"], &1["back"]})

    characters = json_response(get(conn, ~p"/api/v1/plays/#{play.code}/characters"), 200)
    assert %{"name" => "ANA", "description" => "dama"} = hd(characters["data"])
  end

  test "a play's form is the curator's, served beside is_verse", %{conn: conn, play: play} do
    {:ok, _} = Playcode.Catalogue.update_play(play, %{form: "prose"})

    assert %{"form" => "prose", "is_verse" => true} =
             json_response(get(conn, ~p"/api/v1/plays/API0001"), 200)

    assert %{"data" => [%{"form" => "prose", "is_verse" => true}]} =
             json_response(get(conn, ~p"/api/v1/plays?search=Lope"), 200)
  end

  test "a play's characters", %{conn: conn} do
    assert %{
             "data" => [
               %{
                 "xml_id" => "REY",
                 "name" => "EL REY",
                 "description" => "de Castilla",
                 "actor" => "Mr. Betterton"
               }
             ]
           } = json_response(get(conn, ~p"/api/v1/plays/API0001/characters"), 200)
  end

  test "a play's text, division by division", %{conn: conn} do
    body = json_response(get(conn, ~p"/api/v1/plays/API0001/text"), 200)

    assert %{"code" => "API0001", "divisions" => divisions} = body
    act = Enum.find(divisions, &(&1["title"] == "ACTO I"))

    assert [
             %{"type" => "speech", "speaker" => "EL REY", "children" => [lg]},
             %{"type" => "stage_direction", "content" => "Vase"}
           ] = act["elements"]

    assert %{
             "verse_type" => "redondilla",
             "children" => [%{"content" => "Primer verso", "line_number" => 1}]
           } = lg
  end

  test "a play's statistics", %{conn: conn} do
    body = json_response(get(conn, ~p"/api/v1/plays/API0001/statistics"), 200)

    assert body["total_verses"] == 1
    assert body["total_stage_directions"] == 1
  end

  test "an unknown or archived play is a JSON 404 on every endpoint", %{conn: conn, play: play} do
    {:ok, _} = Playcode.Catalogue.delete_play(play)

    for code <- ["NOPE0000", "API0001"], suffix <- ["", "/characters", "/text", "/statistics"] do
      assert json_response(get(conn, "/api/v1/plays/#{code}#{suffix}"), 404) == %{
               "error" => "not found"
             },
             "#{code}#{suffix}"
    end
  end

  test "a draft is neither listed nor served", %{conn: conn} do
    Playcode.TestFixtures.play_fixture(%{"code" => "API0003", "title" => "Borrador de la API"})

    %{"data" => plays} = json_response(get(conn, ~p"/api/v1/plays"), 200)
    refute "API0003" in Enum.map(plays, & &1["code"])

    for suffix <- ["", "/characters", "/text", "/statistics"] do
      assert json_response(get(conn, "/api/v1/plays/API0003#{suffix}"), 404) == %{
               "error" => "not found"
             },
             suffix
    end
  end
end
