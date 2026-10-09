defmodule Playcode.Export.StaticSite.Edition do
  @moduledoc """
  One play prepared for the static site: which page each division goes on, the
  anchor and citation reference of every line, the ghost text that aligns a split
  verse, and where each metrical passage starts. The pages and the search index both
  read it, so a line's address is decided once.
  """

  alias Playcode.{Bibliography, Catalogue, PlayContent, Statistics}
  alias Playcode.PlayContent.Note
  alias Playcode.Statistics.Metrics

  defstruct [
    :play,
    :bibliography,
    :characters,
    :divisions,
    :stats,
    :pages,
    :items,
    :anchors,
    :refs,
    :ghosts,
    :passage_starts,
    :page_of
  ]

  @doc "Loads play `id` and everything the site derives from it."
  def load(id) do
    # The play first: its content_version is what build.json records, so content read
    # after it can only be newer. A play edited mid-load stays flagged as changed, never
    # published stale and recorded as current.
    play = Catalogue.get_play_with_all!(id)
    divisions = PlayContent.load_play_content(id)
    items = Metrics.items(divisions)
    pages = pages(divisions, items)

    %__MODULE__{
      play: play,
      bibliography: Bibliography.list_for_play(id),
      characters: PlayContent.list_characters(id),
      divisions: divisions,
      stats: Statistics.get_statistics(id).data,
      pages: pages,
      items: items,
      anchors: anchors(items, pages),
      refs: refs(items),
      ghosts: ghosts(items),
      passage_starts: passage_starts(Metrics.passages(items)),
      page_of: page_of(pages, items)
    }
  end

  @doc "Each page with the pages before and after it: `{page, previous, next}`."
  def neighbours(pages), do: Enum.zip([pages, [nil | pages], Enum.drop(pages, 1) ++ [nil]])

  @doc "An act number in Roman numerals."
  def roman(n) do
    [{10, "X"}, {9, "IX"}, {5, "V"}, {4, "IV"}, {1, "I"}]
    |> Enum.reduce({n, ""}, fn {value, numeral}, {left, acc} ->
      {rem(left, value), acc <> String.duplicate(numeral, div(left, value))}
    end)
    |> elem(1)
  end

  # A division with more text than this gets a page per scene too, so that no act page
  # outgrows its 80 KB (gzipped) budget: on the dev corpus the largest pages that fit hold
  # 71 KB of text; the three that did not, 200–218 KB.
  @split_bytes 120_000

  # Every top-level division with text gets a page: acts are act-N by their ordinal
  # among all acts, as in the statistics; anything else is named by its type, with
  # -2, -3 for repeats. The cast list goes on the title page. A division over
  # @split_bytes with two or more scenes also gets a page per scene, after its own.
  defp pages(divisions, items) do
    bytes =
      Enum.reduce(items, %{}, fn item, acc ->
        Map.update(acc, item.division.id, text_bytes(item), &(&1 + text_bytes(item)))
      end)

    {pages, _counts} =
      Enum.map_reduce(divisions, %{}, fn division, counts ->
        base = if division.type in Metrics.act_types(), do: "act", else: division.type
        n = Map.get(counts, base, 0) + 1
        slug = if base == "act" or n > 1, do: "#{base}-#{n}", else: base
        title = division.title || String.capitalize(division.type)
        page = %{slug: slug, title: title, division: division, scene: nil, split: false}
        {page, Map.put(counts, base, n)}
      end)

    pages
    |> Enum.reject(&(&1.division.type == "elenco" or empty?(&1.division)))
    |> Enum.flat_map(fn page ->
      scenes = Enum.reject(page.division.children, &(&1.loaded_elements == []))

      if Map.get(bytes, page.division.id, 0) > @split_bytes and length(scenes) >= 2 do
        [%{page | split: true} | Enum.map(scenes, &scene_page_for(page, &1))]
      else
        [page]
      end
    end)
  end

  defp text_bytes(item), do: byte_size(item.element.content || "")

  defp scene_page_for(page, scene) do
    %{
      slug: "#{page.slug}-s#{scene.position + 1}",
      title: "#{page.title}, #{scene_title(scene)}",
      division: page.division,
      scene: scene,
      split: false
    }
  end

  @doc "A scene's heading, or its number when it has none."
  def scene_title(scene), do: scene.title || "Scene #{scene.position + 1}"

  @doc "The notes in a page's text, in reading order: the endnotes it lists."
  def page_notes(%{scene: nil, split: false, division: division}),
    do: Note.reading_order(division)

  def page_notes(%{scene: nil, split: true, division: division}),
    do: Note.reading_order(%{division | children: []})

  def page_notes(%{scene: scene, division: division}),
    do: division.notes ++ Note.reading_order(scene)

  @doc "The page a scene has to itself, or nil when it shares its division's page."
  def scene_page(%__MODULE__{pages: pages}, scene),
    do: Enum.find(pages, &(&1.scene && &1.scene.id == scene.id))

  defp empty?(division),
    do:
      division.loaded_elements == [] and Enum.all?(division.children, &(&1.loaded_elements == []))

  defp page_of(pages, items) do
    slug_of =
      Map.new(pages, fn
        %{scene: nil} = page -> {page.division.id, page.slug}
        page -> {page.scene.id, page.slug}
      end)

    for item <- items,
        slug when not is_nil(slug) <-
          [(item.scene && slug_of[item.scene.id]) || slug_of[item.division.id]],
        into: %{},
        do: {item.element.id, slug}
  end

  # A verse is `l<number>`. A play that numbers each scene from 1 gets
  # `l<act>-<scene>-<number>`; anything without a number is `p<n>`, counted through
  # the play. A clash left after that (a data error) gets a numeric suffix.
  defp anchors(items, pages) do
    restarts? = restarts?(items)

    {elements, _state} =
      Enum.map_reduce(items, {MapSet.new(), 0}, fn item, {used, p} ->
        {base, p} =
          case item.element.line_number do
            n when is_integer(n) and restarts? ->
              {"l#{item.act || 0}-#{scene_ordinal(item)}-#{n}", p}

            n when is_integer(n) ->
              {"l#{n}", p}

            nil ->
              {"p#{p + 1}", p + 1}
          end

        anchor = unique(base, used, 1)
        {{item.element.id, anchor}, {MapSet.put(used, anchor), p}}
      end)

    divisions =
      pages
      |> Enum.reject(& &1.scene)
      |> Enum.flat_map(fn page ->
        scenes = Enum.map(page.division.children, &{&1.id, "#{page.slug}-s#{&1.position + 1}"})
        [{page.division.id, page.slug} | scenes]
      end)

    Map.new(elements ++ divisions)
  end

  defp unique(base, used, 1),
    do: if(MapSet.member?(used, base), do: unique(base, used, 2), else: base)

  defp unique(base, used, k) do
    candidate = "#{base}-#{k}"
    if MapSet.member?(used, candidate), do: unique(base, used, k + 1), else: candidate
  end

  defp restarts?(items) do
    numbers = for %{element: %{line_number: n}} when is_integer(n) <- items, do: n
    length(numbers) != length(Enum.uniq(numbers))
  end

  defp scene_ordinal(%{scene: nil}), do: 0
  defp scene_ordinal(%{scene: scene}), do: scene.position + 1

  # How a line is cited in search results: "II, 1236"; "II.3, 45" when the play
  # numbers each scene from 1; the division alone for prose and stage directions.
  defp refs(items) do
    restarts? = restarts?(items)

    Map.new(items, fn item ->
      where = where(item)
      where = if restarts? and item.scene, do: "#{where}.#{scene_ordinal(item)}", else: where
      {item.element.id, if(item.number, do: "#{where}, #{item.number}", else: where)}
    end)
  end

  defp where(%{act: act}) when is_integer(act), do: roman(act)
  defp where(%{division: division}), do: division.title || String.capitalize(division.type)

  # The content of a split verse's earlier fragments, rendered invisible before an M or
  # F fragment so it starts where the previous fragment ended. Content, markers and all:
  # the page draws it as the fragments themselves are drawn, so a stage direction in an
  # earlier fragment is hidden in the lead as it is in the fragment (`Components.el/1`).
  defp ghosts(items) do
    {ghosts, _open} =
      items
      |> Enum.filter(&(&1.kind == :verse))
      |> Enum.reduce({%{}, []}, fn %{element: el}, {ghosts, open} ->
        text = el.content

        case el.part do
          "I" ->
            {ghosts, [text]}

          part when part in ["M", "F"] and open != [] ->
            ghosts = Map.put(ghosts, el.id, open |> Enum.reverse() |> Enum.join(" "))
            {ghosts, if(part == "M", do: [text | open], else: [])}

          _ ->
            {ghosts, []}
        end
      end)

    ghosts
  end

  defp passage_starts(passages) do
    for %{form: form, element_ids: [first | _]} <- passages, form != "unmarked", into: %{} do
      {first, form}
    end
  end
end
