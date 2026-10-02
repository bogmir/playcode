defmodule PlaycodeWeb.API.PlayController do
  use PlaycodeWeb, :controller

  alias Playcode.{Catalogue, PlayContent, Statistics}
  alias Playcode.Catalogue.Play

  # GET /api/v1/plays
  def index(conn, params) do
    sort = sort_atom(params["sort"])
    plays = Catalogue.list_plays(search: params["search"], sort: sort)

    json(conn, %{
      data: Enum.map(plays, &play_summary/1),
      meta: %{total: length(plays)}
    })
  end

  # GET /api/v1/plays/:code
  def show(conn, %{"code" => code}) do
    play = Catalogue.get_play_by_code_with_all!(code)
    json(conn, play_detail(play))
  rescue
    Ecto.NoResultsError -> not_found(conn)
  end

  # GET /api/v1/plays/:code/characters
  def characters(conn, %{"code" => code}) do
    play = Catalogue.get_play_by_code!(code)
    characters = PlayContent.list_characters(play.id)

    json(conn, %{
      data: Enum.map(characters, &character_json/1)
    })
  rescue
    Ecto.NoResultsError -> not_found(conn)
  end

  # GET /api/v1/plays/:code/text
  def text(conn, %{"code" => code}) do
    play = Catalogue.get_play_by_code!(code)
    divisions = PlayContent.load_play_content(play.id)

    json(conn, %{
      code: play.code,
      title: play.title,
      divisions: Enum.map(divisions, &serialize_division/1)
    })
  rescue
    Ecto.NoResultsError -> not_found(conn)
  end

  # GET /api/v1/plays/:code/statistics
  def statistics(conn, %{"code" => code}) do
    play = Catalogue.get_play_by_code!(code)
    statistic = Statistics.get_statistics(play.id)

    if statistic do
      json(conn, statistic.data)
    else
      json(conn, %{})
    end
  rescue
    Ecto.NoResultsError -> not_found(conn)
  end

  # --- Serializers ---

  defp play_summary(play) do
    %{
      code: play.code,
      url: play_url(play.code),
      title: play.title,
      author: play.author_name,
      verse_count: play.verse_count,
      is_verse: play.is_verse,
      form: Play.form(play)
    }
  end

  defp play_detail(play) do
    %{
      code: play.code,
      url: play_url(play.code),
      title: play.title,
      original_title: play.original_title,
      author: play.author_name,
      verse_count: play.verse_count,
      is_verse: play.is_verse,
      form: Play.form(play),
      pub_place: play.pub_place,
      publication_date: play.publication_date,
      publisher: play.publisher,
      licence_url: play.licence_url,
      licence_text: play.licence_text,
      availability_note: play.availability_note,
      editors: Enum.map(play.editors, &editor_json/1),
      sources: Enum.map(play.sources, &source_json/1),
      editorial_notes: Enum.map(play.editorial_notes, &note_json/1)
    }
  end

  defp editor_json(editor) do
    %{name: editor.person_name, role: editor.role}
  end

  defp source_json(source) do
    %{
      author: source.author,
      editor: source.editor,
      editor_role: source.editor_role,
      title: source.title,
      pub_date: source.pub_date,
      pub_place: source.pub_place,
      publisher: source.publisher,
      note: source.note
    }
  end

  defp note_json(note) do
    %{heading: note.heading, content: note.content, section_type: note.section_type}
  end

  defp character_json(char) do
    %{
      xml_id: char.xml_id,
      name: char.name,
      description: char.description,
      is_hidden: char.is_hidden
    }
  end

  defp serialize_division(division) do
    %{
      id: division.id,
      type: division.type,
      title: division.title,
      position: division.position,
      elements: division |> Map.get(:loaded_elements, []) |> Enum.map(&serialize_element/1),
      children: division |> Map.get(:children, []) |> Enum.map(&serialize_division/1)
    }
  end

  defp serialize_element(%{type: "speech"} = element) do
    %{
      type: "speech",
      speaker: element.speaker_label,
      is_aside: element.is_aside,
      children: element |> Map.get(:children, []) |> Enum.map(&serialize_element/1)
    }
  end

  defp serialize_element(%{type: "line_group"} = element) do
    %{
      type: "line_group",
      verse_type: element.verse_type,
      children: element |> Map.get(:children, []) |> Enum.map(&serialize_element/1)
    }
  end

  defp serialize_element(%{type: "verse_line"} = element) do
    %{
      type: "verse_line",
      content: element.content,
      line_number: element.line_number,
      part: element.part,
      is_aside: element.is_aside,
      rend: element.rend
    }
  end

  defp serialize_element(%{type: "stage_direction"} = element) do
    %{type: "stage_direction", content: element.content}
  end

  defp serialize_element(%{type: "prose"} = element) do
    %{type: "prose", content: element.content, is_aside: element.is_aside}
  end

  defp serialize_element(element) do
    %{type: element.type, content: element.content}
  end

  defp play_url(code), do: PlaycodeWeb.Endpoint.url() <> "/plays/#{code}"

  # --- Helpers ---

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{error: "not found"})
  end

  defp sort_atom("author_sort"), do: :author_sort
  defp sort_atom("code"), do: :code
  defp sort_atom(_), do: :title_sort
end
