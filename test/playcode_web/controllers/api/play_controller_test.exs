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
          source_desc: "<bibl><title>Primera parte</title></bibl>",
          front: """
          <div type="elenco"><castList>
            <castItem><role xml:id="REY">EL REY</role><roleDesc>de Castilla</roleDesc></castItem>
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
    assert [%{"title" => "Primera parte"}] = body["sources"]
  end

  test "a play's form is the curator's, served beside is_verse", %{conn: conn, play: play} do
    {:ok, _} = Playcode.Catalogue.update_play(play, %{form: "prose"})

    assert %{"form" => "prose", "is_verse" => true} =
             json_response(get(conn, ~p"/api/v1/plays/API0001"), 200)

    assert %{"data" => [%{"form" => "prose", "is_verse" => true}]} =
             json_response(get(conn, ~p"/api/v1/plays?search=Lope"), 200)
  end

  test "a play's characters", %{conn: conn} do
    assert %{"data" => [%{"xml_id" => "REY", "name" => "EL REY", "description" => "de Castilla"}]} =
             json_response(get(conn, ~p"/api/v1/plays/API0001/characters"), 200)
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
end
