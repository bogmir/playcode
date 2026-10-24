defmodule Playcode.Export.StaticSite.Edition do
  @moduledoc """
  One play prepared for the static site: which page each division goes on, where each
  paratext and cast list prints, the anchor and citation reference of every line, the
  ghost text that aligns a split verse, where each metrical passage and each aside starts,
  and where each note is. The pages and the search index both read it, so a line's or a note's address
  is decided once.
  """

  alias Playcode.{Bibliography, Catalogue, Outline, Performances, PlayContent, Statistics}
  alias Playcode.Catalogue.Paratext
  alias Playcode.PlayContent.{Division, Element, InlineMarkup, Note}
  alias Playcode.Statistics.Metrics

  defstruct [
    :play,
    :bibliography,
    :performances,
    :characters,
    :divisions,
    :stats,
    :pages,
    :front,
    :before,
    :back,
    :contents,
    :item_pages,
    :items,
    :anchors,
    :refs,
    :ghosts,
    :passage_starts,
    :aside_starts,
    :page_of,
    :notes,
    :variants,
    :folio
  ]

  @doc "Loads play `id` and everything the site derives from it."
  def load(id) do
    # The play first: its content_version is what build.json records, so content read
    # after it can only be newer. A play edited mid-load stays flagged as changed, never
    # published stale and recorded as current.
    play = Catalogue.get_play_with_all!(id)
    divisions = PlayContent.load_play_content(id, variants: play.show_variants)
    items = Metrics.items(divisions)
    pages = pages(divisions, items)
    outline = outline(play.paratexts, divisions, pages)
    refs = refs(items)

    %__MODULE__{
      play: play,
      bibliography: Bibliography.list_for_play(id),
      performances: Performances.list_for_play(id),
      characters: PlayContent.list_characters(id),
      divisions: divisions,
      stats: Statistics.get_statistics(id).data,
      pages: pages,
      front: outline.front,
      before: outline.before,
      back: outline.back,
      contents: outline.contents,
      item_pages: outline.item_pages,
      items: items,
      anchors: Map.merge(anchors(items, pages), outline.anchors),
      refs: refs,
      ghosts: ghosts(items),
      passage_starts: passage_starts(Metrics.passages(items)),
      aside_starts: aside_starts(items),
      page_of: page_of(pages, items),
      notes: notes(divisions, items, pages, refs),
      variants: divisions |> Note.reading_order() |> Enum.any?(&Note.variant?/1),
      folio: Element.folio_passages?(divisions)
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
  # -2, -3 for repeats. A cast list gets none (see `outline/3`). A division over
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

        page = %{slug: slug, title: title(division), division: division, scene: nil, split: false}
        {page, Map.put(counts, base, n)}
      end)

    pages
    |> Enum.reject(&(&1.division.type == "elenco" or empty?(&1.division)))
    |> Enum.flat_map(fn page ->
      scenes =
        page.division
        |> Division.numbered_scenes()
        |> Enum.reject(fn {scene, _n} -> scene.loaded_elements == [] end)

      if Map.get(bytes, page.division.id, 0) > @split_bytes and length(scenes) >= 2 do
        [%{page | split: true} | Enum.map(scenes, &scene_page_for(page, &1))]
      else
        [page]
      end
    end)
  end

  defp text_bytes(item), do: byte_size(item.element.content || "")

  defp scene_page_for(page, {scene, n}) do
    %{
      slug: "#{page.slug}-s#{n}",
      title: "#{page.title}, #{scene_title(scene, n)}",
      division: page.division,
      scene: scene,
      number: n,
      split: false
    }
  end

  # Where each paratext and cast list prints. Those before the first division of the text
  # go on the title page (`front`). Any other prints at the top of the next page, above its
  # heading (`before`, by the id of that page's division or scene), and those after the
  # last page at its foot (`back`). An act's own lists print where they stand on its page;
  # on an act split by scene, those that open it on the act's page, any other on the page
  # of the scene after it. A play with no
  # page of text prints them all on the title page.
  defp outline(paratexts, divisions, []) do
    %{
      front: for(item <- Outline.items(paratexts, divisions), not text_division?(item), do: item),
      before: %{},
      back: [],
      contents: [],
      item_pages: %{},
      anchors: item_anchors(paratexts, divisions)
    }
  end

  defp outline(paratexts, divisions, pages) do
    {front, rest} =
      paratexts
      |> Outline.items(divisions)
      |> Outline.placement()
      |> Enum.split_with(&match?({:front, _item}, &1))

    rest = Enum.map(rest, &elem(&1, 1))
    page_of = Map.new(pages, &{(&1.scene || &1.division).id, &1})
    reading = Enum.flat_map(rest, &reading(&1, page_of))

    {before, back} =
      Enum.reduce(reading, {%{}, []}, fn
        {:page, page}, {before, pending} ->
          {Map.put(before, (page.scene || page.division).id, Enum.reverse(pending)), []}

        {:item, item}, {before, pending} ->
          {before, [item | pending]}
      end)

    last = List.last(pages)

    item_pages =
      for(
        {id, items} <- before,
        item <- items,
        into: %{},
        do: {item.id, page_of[id].slug}
      )
      |> Map.merge(Map.new(back, &{&1.id, last.slug}))
      |> Map.merge(
        for page <- pages,
            is_nil(page.scene),
            list <- own_lists(page),
            into: %{},
            do: {list.id, page.slug}
      )

    %{
      front: Enum.map(front, &elem(&1, 1)),
      before: before,
      back: Enum.reverse(back),
      contents: for(item <- rest, entry <- contents(item, page_of), do: entry),
      item_pages: item_pages,
      anchors: item_anchors(paratexts, divisions)
    }
  end

  # The outline after the title page as a reader meets it: pages, and the items between.
  defp reading(%Paratext{} = paratext, _page_of), do: [{:item, paratext}]
  defp reading(%Division{type: "elenco"} = list, _page_of), do: [{:item, list}]

  defp reading(division, page_of) do
    case page_of[division.id] do
      nil ->
        for %{type: "elenco"} = list <- division.children, do: {:item, list}

      %{split: true} = page ->
        {_opening, rest} = Division.split_opening_lists(division.children)
        [{:page, page} | Enum.flat_map(rest, &reading_child(&1, page_of))]

      page ->
        [{:page, page}]
    end
  end

  # The lists a division's own page prints: all of them; on a page split by scene, those
  # that open the act, as the others print on the page of the scene after them.
  defp own_lists(%{split: true, division: division}),
    do: division.children |> Division.split_opening_lists() |> elem(0)

  defp own_lists(page), do: Enum.filter(page.division.children, &(&1.type == "elenco"))

  defp reading_child(%{type: "elenco"} = list, _page_of), do: [{:item, list}]
  defp reading_child(scene, page_of), do: page_entry(scene, page_of)

  # The Contents' top-level entries after the title page: each division's page, each
  # paratext and cast list between them.
  defp contents(item, page_of) do
    if text_division?(item), do: page_entry(item, page_of), else: [{:item, item}]
  end

  defp page_entry(division, page_of),
    do: for(page <- List.wrap(page_of[division.id]), do: {:page, page})

  defp text_division?(%Division{type: type}), do: type != "elenco"
  defp text_division?(_paratext), do: false

  # A paratext is `paratext-<n>`, its number in outline order; a cast list before or
  # between the acts `elenco`, `elenco-2`…, as a page is named; an act's own list is named
  # after its page in `anchors/2`.
  defp item_anchors(paratexts, divisions) do
    items = Outline.items(paratexts, divisions)

    paratext_anchors =
      for {paratext, n} <- items |> Enum.filter(&match?(%Paratext{}, &1)) |> Enum.with_index(1),
          do: {paratext.id, "paratext-#{n}"}

    list_anchors =
      for {list, n} <-
            items |> Enum.filter(&match?(%Division{type: "elenco"}, &1)) |> Enum.with_index(1),
          do: {list.id, numbered("elenco", n)}

    Map.new(paratext_anchors ++ list_anchors)
  end

  defp numbered(base, 1), do: base
  defp numbered(base, n), do: "#{base}-#{n}"

  # A division's heading. With none, its type, and an act's number as the file gives it, in
  # Roman numerals as the corpus writes its headings ("Act I"): 48 files leave every act's
  # head empty and number it in `n`.
  defp title(%{title: title}) when title not in [nil, ""], do: InlineMarkup.plain(title)

  defp title(%{type: type, number: n}) when is_integer(n) and n > 0,
    do: "#{String.capitalize(type)}#{if type in Metrics.act_types(), do: " #{roman(n)}"}"

  defp title(division), do: String.capitalize(division.type)

  @doc "A scene's heading, or its number `n` when it has none."
  def scene_title(%{title: nil}, n), do: "Scene #{n}"
  def scene_title(scene, _n), do: InlineMarkup.plain(scene.title)

  @doc "The notes in a page's text, in reading order: the endnotes it lists."
  def page_notes(%{scene: nil, split: false, division: division}),
    do: Note.reading_order(division)

  def page_notes(%{scene: nil, split: true, division: division}),
    do: Note.reading_order(%{division | children: []})

  def page_notes(%{scene: scene, division: division}),
    do: division.notes ++ Note.reading_order(scene)

  # Each note once, in reading order, as the search index and the Notes page read it:
  # the first page that lists it (a split act's heading note is on the act's own page,
  # not on every scene page that prints the heading again), how a search result cites
  # where it is, the speakers there, and the word it glosses. A note on no page (in a
  # cast list) is left out. Variants are not listed: they are the apparatus, opened from
  # the text.
  defp notes(divisions, items, pages, refs) do
    slug_of =
      Enum.reduce(pages, %{}, fn page, acc ->
        Enum.reduce(page_notes(page), acc, &Map.put_new(&2, &1.id, page.slug))
      end)

    title_of = Map.new(pages, &{&1.slug, &1.title})
    item_of = Map.new(items, &{&1.element.id, &1})

    first_of =
      Enum.reduce(items, %{}, fn
        %{speech: %{id: id}} = item, acc -> Map.put_new(acc, id, item)
        _item, acc -> acc
      end)

    for %{note: note, anchor: anchor} = at <- Note.with_anchors(divisions),
        not Note.variant?(note),
        slug when not is_nil(slug) <- [slug_of[note.id]] do
      item = item_of[anchor.id] || first_of[anchor.id]

      %{
        note: note,
        slug: slug,
        ref: note_ref(anchor, at, item, refs, title_of[slug]),
        speakers: if(item, do: item.speakers, else: []),
        glossed: Note.glossed(note, PlayContent.anchor_text(anchor))
      }
    end
  end

  # A line's, or a speech's first line's, citation; a scene heading's scene; otherwise the
  # title of the page the note is on.
  defp note_ref(%Division{} = scene, %{scene: scene, division: division}, _item, _refs, _title),
    do: "#{title(division)}, #{scene_title(scene, scene_number(division, scene))}"

  defp note_ref(_anchor, _at, %{element: element}, refs, _title), do: refs[element.id]
  defp note_ref(_anchor, _at, nil, _refs, title), do: title

  defp scene_number(division, scene) do
    Enum.find_value(Division.numbered_scenes(division), fn {child, n} ->
      child.id == scene.id && n
    end)
  end

  @doc """
  The paratexts and cast lists printed at the top of `page`: above its heading, or on a
  scene's page between its act's heading and the scene.
  """
  def before(%__MODULE__{before: before}, page),
    do: Map.get(before, (page.scene || page.division).id, [])

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
  # `l<act>-<scene>-<number>`; a verse with no number is its identifier (`es-0412`), so a
  # line added before it does not move it; anything else is `p<n>`, counted through the
  # play. A clash left after that (a data error) gets a numeric suffix.
  defp anchors(items, pages) do
    restarts? = restarts?(items)

    {elements, _state} =
      Enum.map_reduce(items, {MapSet.new(), 0}, fn item, {used, p} ->
        {base, p} =
          case item.element do
            %{line_number: n} when is_integer(n) and restarts? ->
              {"l#{item.act || 0}-#{scene_ordinal(item)}-#{n}", p}

            %{line_number: n} when is_integer(n) ->
              {"l#{n}", p}

            %{line_id: id} when is_binary(id) ->
              {id, p}

            _ ->
              {"p#{p + 1}", p + 1}
          end

        anchor = unique(base, used, 1)
        {{item.element.id, anchor}, {MapSet.put(used, anchor), p}}
      end)

    divisions =
      pages
      |> Enum.reject(& &1.scene)
      |> Enum.flat_map(fn page ->
        [{page.division.id, page.slug} | child_anchors(page)]
      end)

    Map.new(elements ++ divisions)
  end

  defp unique(base, used, 1),
    do: if(MapSet.member?(used, base), do: unique(base, used, 2), else: base)

  defp unique(base, used, k) do
    candidate = "#{base}-#{k}"
    if MapSet.member?(used, candidate), do: unique(base, used, k + 1), else: candidate
  end

  # A play that numbers each scene from 1 gives a number again in another scene or division.
  # One repeated within a scene (a data error, or a number a curator typed again) gets a
  # suffix (`unique/3`) instead: taken for a restart, it changed every anchor in the play.
  defp restarts?(items) do
    for(
      %{element: %{line_number: n}} = item <- items,
      is_integer(n),
      uniq: true,
      do: {n, {item.division.id, item.scene && item.scene.id}}
    )
    |> Enum.frequencies_by(&elem(&1, 0))
    |> Enum.any?(fn {_n, units} -> units > 1 end)
  end

  # A division's children on its page: a scene by its number, `<page>-s<n>`; a cast list by
  # its count among the division's lists, `<page>-elenco`, `<page>-elenco-2`…
  defp child_anchors(page) do
    {anchors, _counts} =
      Enum.map_reduce(page.division.children, {0, 0}, fn
        %{type: "elenco"} = list, {scenes, lists} ->
          {{list.id, numbered("#{page.slug}-elenco", lists + 1)}, {scenes, lists + 1}}

        scene, {scenes, lists} ->
          {{scene.id, "#{page.slug}-s#{scenes + 1}"}, {scenes + 1, lists}}
      end)

    anchors
  end

  defp scene_ordinal(item), do: item.scene_number || 0

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
  defp where(%{division: division}), do: title(division)

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

  # The verses the margin names "aparte": each where an aside starts
  # (`Element.asides_started/1`), and the first of a speech's aside verses in a row, so an
  # aside carried into another speaker's speech is named again for the new speaker.
  defp aside_starts(items) do
    verses = Enum.filter(items, &(&1.kind == :verse))

    first_in_speech =
      for [%{element: %{is_aside: true} = el} | _] <-
            Enum.chunk_by(verses, &{&1.speech && &1.speech.id, &1.element.is_aside}),
          do: el.id

    starting = for %{element: el} <- verses, Element.asides_started(el) > 0, do: el.id

    MapSet.new(first_in_speech ++ starting)
  end
end
