defmodule PlaycodeWeb.DemoUIController do
  @moduledoc false

  use PlaycodeWeb, :controller

  alias PlaycodeWeb.Demo.UIDemoData

  defp with_app_layout(conn), do: put_layout(conn, html: {PlaycodeWeb.Layouts, :app})
  defp with_admin_layout(conn), do: put_layout(conn, html: {PlaycodeWeb.Layouts, :admin})

  def index(conn, _params) do
    conn
    |> with_app_layout()
    |> render(:index, page_title: "UI Demos", breadcrumbs: [%{label: "UI Demos"}])
  end

  def public_catalogue(conn, _params) do
    conn
    |> with_app_layout()
    |> render(:public_catalogue,
      page_title: "Play Catalogue (Demo)",
      breadcrumbs: [%{label: "Catalogue"}],
      plays: UIDemoData.plays_list(),
      search: ""
    )
  end

  def public_play(conn, _params) do
    conn
    |> with_app_layout()
    |> render(:public_play,
      page_title: "Play Show (Demo)",
      breadcrumbs: [
        %{label: "Catalogue", to: "/demo/ui/public/catalogue"},
        %{label: UIDemoData.play().title}
      ],
      play: UIDemoData.play(),
      characters: UIDemoData.characters(),
      statistic: UIDemoData.statistic(),
      active_tab: :text,
      show_line_numbers: true,
      show_stage_directions: true,
      sidebar_open: true
    )
  end

  def admin_import(conn, params) do
    conn =
      case params["flash"] do
        "duplicate" ->
          put_flash(conn, :error, "Play with code DAMA01 already exists")

        "success" ->
          put_flash(conn, :info, "Successfully imported 1 play(s).")

        _ ->
          conn
      end

    conn
    |> with_admin_layout()
    |> render(:admin_import,
      page_title: "Import TEI-XML (Demo)",
      successes: [{"example.xml", "La Dama Boba", "DAMA01"}]
    )
  end

  def admin_plays(conn, _params) do
    conn
    |> with_admin_layout()
    |> render(:admin_plays,
      page_title: "Admin - Plays (Demo)",
      plays: UIDemoData.plays_list(),
      search: ""
    )
  end

  def admin_play(conn, _params) do
    play = UIDemoData.play()

    conn
    |> with_admin_layout()
    |> render(:admin_play,
      page_title: "Admin: #{play.title} (Demo)",
      play: play,
      characters: UIDemoData.characters(),
      divisions: [
        %{
          title: "Acto I",
          type: "acto",
          number: 1,
          children: [%{title: "Escena I", type: "escena", number: 1}]
        },
        %{
          title: "Acto II",
          type: "acto",
          number: 2,
          children: [%{title: "Escena I", type: "escena", number: 1}]
        }
      ],
      statistic: UIDemoData.statistic(),
      play_context: %{play: play, active_tab: :overview}
    )
  end
end
