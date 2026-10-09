defmodule PlaycodeWeb.AccessibilityTest do
  @moduledoc """
  Every page, rendered with data in it, checked for what a screen reader or a keyboard
  user cannot get past and what axe reports as serious: a form control or a link or
  button with no name, an `aria-label` on an element whose role forbids one, content
  outside every landmark, and a scrolling box the keyboard cannot reach. Colour
  contrast needs a browser and is not checked here: the theme's colours are tuned to
  4.5:1, and muted text is never lighter than `text-base-content/70`.

  The names follow axe's rules, not the strictest reading of WCAG: a placeholder or
  a title names a control, as axe accepts.
  """
  use PlaycodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playcode.TestFixtures

  alias Playcode.Catalogue

  setup %{conn: conn} do
    structure = play_with_structure_fixture()
    play = mark_complete!(structure.play)

    {:ok, _} = Catalogue.create_play_source(%{play_id: play.id, title: "Fuente", position: 1})

    {:ok, _} =
      Catalogue.create_play_editor(%{
        play_id: play.id,
        person_name: "Editora",
        role: "editor",
        position: 1
      })

    {:ok, _} =
      Catalogue.create_play_editorial_note(%{
        play_id: play.id,
        section_type: "nota",
        heading: "Nota",
        content: "Texto",
        position: 1
      })

    # A second character, so a selected speech offers one to add.
    {:ok, _} =
      Playcode.PlayContent.create_character(%{
        play_id: play.id,
        xml_id: "BETA",
        name: "BETA",
        position: 2
      })

    play_place_fixture(play, place_fixture())
    bibliography_fixture(play)

    play_fixture(%{
      "title" => "Translated",
      "parent_play_id" => play.id,
      "relationship_type" => "traduccion",
      "is_complete" => true
    })

    %{conn: log_in_user(conn, admin_fixture()), play: play, structure: structure}
  end

  @pages ~w(
    /
    /plays
    /plays/:code
    /plays/:code/compare
    /users/settings
    /admin/plays
    /admin/plays?archived=1
    /admin/plays/new
    /admin/plays/import
    /admin/plays/:id
    /admin/plays/:id/edit
    /admin/plays/:id/editors
    /admin/plays/:id/sources
    /admin/plays/:id/places
    /admin/plays/:id/bibliography
    /admin/plays/:id/content
    /admin/plays/:id/compare
    /admin/places
    /admin/users
    /admin/activity-log
    /admin/export
    /admin/filemaker
  )

  for path <- @pages do
    @path path
    test "#{path} has no barrier", %{conn: conn, play: play} do
      path = @path |> String.replace(":id", play.id) |> String.replace(":code", play.code)

      assert conn |> get(path) |> html_response(200) |> barriers() == []
    end
  end

  test "the log-in and password pages have no barrier" do
    for path <- ~w(/users/log-in /users/reset-password) do
      assert {path, build_conn() |> get(path) |> html_response(200) |> barriers()} == {path, []}
    end
  end

  # Each case is a page and the clicks that open a tab, a selection or a modal on it,
  # made on what the user reads.
  test "what a click opens has no barrier", %{conn: conn, play: play, structure: s} do
    content = "/admin/plays/:id/content"
    tab = &{"nav[aria-label='Editor tabs'] button", &1}
    scene = [tab.("structure"), {"button", "SCENE I"}]
    edit = &{"#element-#{&1.id} button[aria-label='#{t("Edit")}']", nil}

    for {path, clicks} <- [
          {"/admin/plays/:id/editors", [{"button", t("Add editor")}]},
          {"/admin/plays/:id/sources", [{"button", t("Add source")}]},
          {"/admin/plays/:id/bibliography", [{"button", t("New entry")}]},
          {"/admin/plays/:id/bibliography", [{"button", t("Add existing")}]},
          {"/admin/plays/:id/places", [{"button", t("New place")}]},
          {"/admin/places", [{"button", t("New place")}]},
          {content, [tab.(t("Editorial Notes")), {"button", t("Add Note")}]},
          {content, [tab.(t("Cast list")), {"button", t("Add Character")}]},
          {content, [tab.(t("Character Review")), {"button", t("Select all")}]},
          {content, [tab.("content")]},
          {content, [tab.("structure"), {"button", t("Add Act")}]},
          {content, scene},
          {content, scene ++ [{"span", s.speech.speaker_label}]},
          {content, scene ++ [edit.(s.verse_line)]},
          {content, scene ++ [edit.(s.prose)]},
          {content, scene ++ [edit.(s.stage_direction)]}
        ] do
      {:ok, lv, _html} = live(conn, String.replace(path, ":id", play.id))
      for {selector, text} <- clicks, do: lv |> element(selector, text) |> render_click()

      assert {path, clicks, lv |> render() |> barriers()} == {path, clicks, []}
    end
  end

  # --- The checks, over the parsed page -----------------------------------------------

  @landmarks ~w(main header nav aside footer form section)
  @landmark_roles ~w(main banner navigation complementary contentinfo region search form
                     dialog alertdialog alert status log)
  @no_name_roles ~w(label div span p b i em strong small code)
  @focusable ~w(a button input select textarea summary)

  defp barriers(html) do
    tree = html |> LazyHTML.from_document() |> LazyHTML.to_tree()
    ctx = %{ids: index(tree, %{}), labels: labels(tree, %{})}
    tree |> walk([], ctx) |> Enum.uniq()
  end

  defp walk(nodes, ancestors, ctx) when is_list(nodes),
    do: Enum.flat_map(nodes, &walk(&1, ancestors, ctx))

  defp walk({tag, attrs, children} = node, ancestors, ctx) when is_binary(tag) do
    if hidden?(attrs) or tag in ~w(head script style template) do
      []
    else
      check(node, ancestors, ctx) ++ walk(children, [node | ancestors], ctx)
    end
  end

  defp walk(text, ancestors, _ctx) when is_binary(text) do
    if String.trim(text) != "" and not in_landmark?(ancestors),
      do: ["text outside a landmark: #{String.slice(String.trim(text), 0, 40)}"],
      else: []
  end

  defp walk(_comment, _ancestors, _ctx), do: []

  defp check({tag, attrs, children} = node, ancestors, ctx) do
    a = Map.new(attrs)
    what = describe(node)

    [
      control?(tag, a) && blank?(control_name(a, ancestors, ctx)) && "unnamed control: #{what}",
      (tag == "button" || (tag == "a" && a["href"])) && blank?(name(node, ctx)) &&
        "unnamed #{tag}: #{what}",
      tag in @no_name_roles && is_nil(a["role"]) && (a["aria-label"] || a["aria-labelledby"]) &&
        "aria-label on a <#{tag}>: #{what}",
      focusable?(tag, a) && not in_landmark?(ancestors) && "control outside a landmark: #{what}",
      scrolls?(a) && is_nil(a["tabindex"]) && not has_focusable?(children) &&
        "scrolling box the keyboard cannot reach: #{what}"
    ]
    |> Enum.filter(&is_binary/1)
  end

  defp control?("input", a), do: a["type"] not in ~w(hidden submit button reset image)
  defp control?(tag, _a), do: tag in ~w(select textarea)

  defp focusable?(tag, a),
    do: (tag in @focusable and not (tag == "input" and a["type"] == "hidden")) or !!a["tabindex"]

  defp scrolls?(a), do: (a["class"] || "") =~ ~r/\boverflow(-[xy])?-(auto|scroll)\b/

  defp has_focusable?(nodes) do
    Enum.any?(List.wrap(nodes), fn
      {tag, attrs, children} when is_binary(tag) ->
        focusable?(tag, Map.new(attrs)) or has_focusable?(children)

      _ ->
        false
    end)
  end

  defp in_landmark?(ancestors) do
    Enum.any?(ancestors, fn {tag, attrs, _} ->
      a = Map.new(attrs)

      (tag in @landmarks and (tag not in ~w(section form) or named?(a))) or
        a["role"] in @landmark_roles or Map.has_key?(a, "aria-live")
    end)
  end

  defp named?(a), do: Map.has_key?(a, "aria-label") or Map.has_key?(a, "aria-labelledby")

  defp control_name(a, ancestors, ctx) do
    wrapping = Enum.find(ancestors, &match?({"label", _, _}, &1))

    labelled_by(a, ctx) || a["aria-label"] || ctx.labels[a["id"]] ||
      (wrapping && label_text(wrapping)) || a["title"] || a["placeholder"]
  end

  defp name({_, attrs, children}, ctx) do
    a = Map.new(attrs)
    labelled_by(a, ctx) || a["aria-label"] || present(text(children)) || a["title"]
  end

  defp labelled_by(a, ctx) do
    if ids = a["aria-labelledby"],
      do: ids |> String.split() |> Enum.map_join(" ", &text(ctx.ids[&1])) |> present()
  end

  defp label_text({_, _, children}), do: children |> text(~w(select textarea)) |> present()

  # Visible and screen-reader text, with an image's alt; never a control's own options.
  defp text(nodes, skip \\ ~w(select textarea))
  defp text(nil, _skip), do: ""
  defp text(text, _skip) when is_binary(text), do: text
  defp text(nodes, skip) when is_list(nodes), do: Enum.map_join(nodes, &text(&1, skip))

  defp text({tag, attrs, children}, skip) when is_binary(tag) do
    a = Map.new(attrs)

    cond do
      tag in skip or hidden?(attrs) or a["aria-hidden"] == "true" -> ""
      tag == "img" -> a["alt"] || ""
      true -> text(children, skip)
    end
  end

  defp text(_comment, _skip), do: ""

  defp hidden?(attrs), do: Enum.any?(attrs, &match?({"hidden", _}, &1))

  defp present(text), do: if(String.trim(text) != "", do: text)
  defp blank?(text), do: is_nil(text) or String.trim(text) == ""

  defp index(nodes, acc) when is_list(nodes), do: Enum.reduce(nodes, acc, &index/2)

  defp index({tag, attrs, children} = node, acc) when is_binary(tag) do
    acc = if id = Map.new(attrs)["id"], do: Map.put(acc, id, node), else: acc
    index(children, acc)
  end

  defp index(_leaf, acc), do: acc

  defp labels(nodes, acc) when is_list(nodes), do: Enum.reduce(nodes, acc, &labels/2)

  defp labels({"label", attrs, _} = node, acc) do
    case {Map.new(attrs)["for"], label_text(node)} do
      {nil, _} -> labels(elem(node, 2), acc)
      {_, nil} -> labels(elem(node, 2), acc)
      {id, text} -> labels(elem(node, 2), Map.put(acc, id, text))
    end
  end

  defp labels({tag, _attrs, children}, acc) when is_binary(tag), do: labels(children, acc)
  defp labels(_leaf, acc), do: acc

  defp describe({tag, attrs, _}) do
    keep = ~w(id name type href class phx-click)

    attrs
    |> Enum.filter(fn {k, _} -> k in keep end)
    |> Enum.map_join(" ", fn {k, v} -> ~s(#{k}="#{String.slice(v, 0, 60)}") end)
    |> then(&"<#{tag} #{&1}>")
  end
end
