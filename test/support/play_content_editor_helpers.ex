defmodule PlaycodeWeb.PlayContentEditorHelpers do
  @moduledoc """
  What the content editor's test files share: the play they open and the helpers that open a
  tab or read the play back.
  """
  @endpoint PlaycodeWeb.Endpoint

  use PlaycodeWeb, :verified_routes

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Playcode.TestFixtures
  import Playcode.ImportHelpers
  import PlaycodeWeb.ConnCase, only: [t: 1, log_in_user: 2]

  def open_editor(%{conn: conn}) do
    cast =
      ~w(ANA DON)
      |> Enum.map_join(&~s(<castItem><role xml:id="#{&1}">#{&1}</role></castItem>))

    play =
      import_tei!(
        tei(
          front: ~s(<div type="elenco"><castList>#{cast}</castList></div>),
          body: """
          <div1 type="acto" n="1"><head>ACTO PRIMERO</head>
            <div2 type="escena" n="1"><head>ESCENA I</head>
              <stage>Sale el Rey</stage>
              <sp who="#ANA"><speaker>ANA</speaker><lg type="redondilla">
                <l n="1">Primera línea</l><l n="2">Segunda línea</l><l n="3">Tercera línea</l>
              </lg></sp>
            </div2>
          </div1>
          """
        )
      )

    %{conn: log_in_user(conn, user_fixture(role: :researcher)), play: play}
  end

  def open_structure(conn, play) do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/content")
    lv |> element("nav[aria-label='Editor tabs'] button", t("Structure")) |> render_click()
    lv
  end

  def open_scene(conn, play) do
    lv = open_structure(conn, play)
    lv |> element("button", "ESCENA I") |> render_click()
    lv
  end

  # The element card whose text is `content`, as its DOM id.
  def card(lv, content) do
    [id] =
      Regex.run(~r/phx-value-id="([^"]+)"/, lv |> element("span[title='#{content}']") |> render(),
        capture: :all_but_first
      )

    "#element-#{id}"
  end

  def lines(play) do
    play
    |> export_tei()
    |> xml_elements("l")
    |> Enum.map(fn {attrs, text} -> {text, attrs["n"] && String.to_integer(attrs["n"])} end)
  end

  # Regression: archiving a play notifies its topic, and the editor reloaded it through

  def gone, do: t("That item no longer exists. The list has been refreshed.")

  # The play's outline, read back through the contexts, and each item's key as the
  # Structure tab's rows carry it.
  def outline_items(play_id) do
    play_id
    |> Playcode.Catalogue.list_paratexts()
    |> Playcode.Outline.items(Playcode.PlayContent.list_top_divisions(play_id))
  end

  def key(item), do: Playcode.Outline.key(item)

  def open_cast(conn, play) do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/content")
    lv |> element("nav[aria-label='Editor tabs'] button", t("Cast list")) |> render_click()
    lv
  end

  # A character's first entry, the line its name is first given in.
  def entry(play, xml_id) do
    play.id
    |> Playcode.PlayContent.list_cast_lists()
    |> Enum.flat_map(& &1.entries)
    |> Enum.find(&(&1.character && &1.character.xml_id == xml_id))
  end

  def speakers(play) do
    play |> export_tei() |> xml_elements("sp") |> Enum.map(fn {attrs, _} -> attrs["who"] end)
  end

  def loaded(item, key) do
    case Map.get(item, key) do
      list when is_list(list) -> list
      _not_loaded -> []
    end
  end

  # The first division or element of `play`, depth first, for which `fun` is true.
  def row(play, fun) do
    walk = fn walk, items ->
      Enum.flat_map(items, fn item ->
        nested = Enum.flat_map([:children, :loaded_elements], &List.wrap(loaded(item, &1)))
        [item | walk.(walk, nested)]
      end)
    end

    play.id
    |> Playcode.PlayContent.load_play_content()
    |> then(&walk.(walk, &1))
    |> Enum.find(fun)
  end
end
