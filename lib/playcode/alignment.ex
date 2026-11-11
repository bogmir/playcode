defmodule Playcode.Alignment do
  @moduledoc """
  Which original speech each speech of a translation goes with (problem 5,
  `docs/superpowers/specs/2026-11-08-translation-alignment-design.md`). Computed whenever a
  comparison is built, and stored nowhere.

  1. **Characters** pair by name across languages (Antony, Antoine, Antonio) and by where
     in the play they speak, which catches renamed roles (Fool, Bufón).
  2. **Speeches** pair by the sequence of speakers, as a diff does, within each scene when
     both texts have the same scenes, else each act, else the whole play. A speaker
     repeated after a stage direction is an insertion beside a speech of the same speaker,
     and points at it; a cut is a deletion, and is paired with nothing.

  A text is `%{characters: [%{id, name}], speeches: [%{id, act, scene, speakers}]}`,
  speeches in reading order, `speakers` a list of character ids.
  """

  alias Playcode.PlayContent.{Division, Element}

  # ponytail: one-to-one greedy character pairing; merged or split roles stay unpaired.
  @buckets 20
  @threshold 0.6
  # An adaptation's speakers do not follow its original's (proof of concept: median length
  # correlation 0.04), so it keeps the comparison's proportion.
  @paired ~w(traduccion version)

  @doc "Whether `play` is paired with its original by speaker: a translation or a version."
  def paired?(play), do: play.relationship_type in @paired

  @doc """
  Marks each speech of `editions`, `{play, divisions}` as `PlayContent.load_play_content/2`
  gives them, with `pair`: in a translation or version shown beside its original, the place
  among the original's speeches of the one it goes with; in that original, its own place.
  Any other speech gets nil, and the comparison pairs it by proportion.
  """
  def mark_pairs(editions) do
    shown = Map.new(editions, fn {play, divisions} -> {play.id, divisions} end)

    pairs =
      Enum.reduce(editions, %{}, fn {play, divisions}, acc ->
        original = paired?(play) && shown[play.parent_play_id]

        if original,
          do:
            acc |> Map.merge(own_places(original)) |> Map.merge(pair_places(original, divisions)),
          else: acc
      end)

    Enum.map(editions, fn {play, divisions} -> {play, Enum.map(divisions, &mark(&1, pairs))} end)
  end

  @doc "Each speech of `divisions` by id, with its place among them in reading order."
  def own_places(divisions), do: divisions |> text() |> places()

  @doc """
  Each speech of `translation_divisions` by id, with the place among `original_divisions`'
  speeches of the one it goes with; a speech the alignment gives no original is left out.
  """
  def pair_places(original_divisions, translation_divisions) do
    original = text(original_divisions)
    own = places(original)

    for %{id: id, original: o} <- align(original, text(translation_divisions)).speeches,
        o != nil,
        into: %{},
        do: {id, own[o]}
  end

  defp places(text), do: text.speeches |> Enum.with_index() |> Map.new(fn {s, i} -> {s.id, i} end)

  # A play's speeches in reading order, each with its act's and scene's comparison keys
  # (`Division.sync_keys/1`), and the characters who speak them.
  defp text(divisions) do
    speeches =
      for {top, act} <- keyed(divisions),
          {division, scene} <- [{top, nil} | keyed(Map.get(top, :children, []))],
          %{type: "speech"} = el <- Map.get(division, :loaded_elements, []),
          do: {el, act, scene && {act, scene}}

    %{
      characters:
        speeches
        |> Enum.flat_map(fn {el, _, _} -> Element.characters(el) end)
        |> Enum.uniq_by(& &1.id)
        |> Enum.map(&Map.take(&1, [:id, :name, :xml_id, :original_xml_id, :no_original])),
      speeches:
        for {el, act, scene} <- speeches do
          %{
            id: el.id,
            act: act,
            scene: scene,
            speakers: Enum.map(Element.characters(el), & &1.id)
          }
        end
    }
  end

  defp keyed(divisions), do: Enum.zip(divisions, Division.sync_keys(divisions))

  defp mark(division, pairs) do
    division
    |> mark_each(:loaded_elements, fn
      %{type: "speech"} = el -> %{el | pair: pairs[el.id]}
      el -> el
    end)
    |> mark_each(:children, &mark(&1, pairs))
  end

  defp mark_each(map, key, fun) do
    case map do
      %{^key => list} when is_list(list) -> %{map | key => Enum.map(list, fun)}
      _ -> map
    end
  end

  @doc """
  Each character of a translation, by id, with the original character it goes with, as
  `PlayContent.load_play_content/2` gives both texts: the researcher's corrections laid
  over the rule, or, with `corrections: false`, the rule's own pick.
  """
  def character_pairs(original_divisions, translation_divisions, opts \\ []) do
    translation = text(translation_divisions)

    translation =
      if Keyword.get(opts, :corrections, true),
        do: translation,
        else: %{
          translation
          | characters:
              Enum.map(translation.characters, &Map.drop(&1, [:original_xml_id, :no_original]))
        }

    pair_characters(text(original_divisions), translation)
  end

  def align(original, translation) do
    characters = pair_characters(original, translation)
    paired = pair_speeches(original.speeches, translation.speeches, characters)
    hit = MapSet.new(paired, & &1.original)

    %{
      characters: characters,
      speeches: paired,
      unpaired: for(s <- original.speeches, s.id not in hit, do: s.id)
    }
  end

  ## Characters

  # A researcher's corrections first: a character with no original is out, one whose
  # pointer names an original character goes with it. The rule pairs the rest; a pointer
  # naming no one is no correction.
  defp pair_characters(original, translation) do
    by_xml_id = for o <- original.characters, o[:xml_id], into: %{}, do: {o.xml_id, o.id}

    fixed =
      for t <- translation.characters,
          o = by_xml_id[t[:original_xml_id]],
          o && !t[:no_original],
          into: %{},
          do: {t.id, o}

    rest = %{
      translation
      | characters: Enum.reject(translation.characters, &(&1[:no_original] || fixed[&1.id]))
    }

    taken = MapSet.new(Map.values(fixed))
    others = %{original | characters: Enum.reject(original.characters, &(&1.id in taken))}
    Map.merge(by_rule(others, rest), fixed)
  end

  defp by_rule(original, translation) do
    o_profiles = profiles(original.speeches)
    t_profiles = profiles(translation.speeches)

    scores =
      for t <- translation.characters, o <- original.characters do
        {score(t, o, t_profiles[t.id], o_profiles[o.id]), t.id, o.id}
      end

    scores
    |> Enum.filter(fn {score, _, _} -> score >= @threshold end)
    |> Enum.sort_by(&elem(&1, 0), :desc)
    |> Enum.reduce({%{}, MapSet.new()}, fn {_, t, o}, {pairs, taken} ->
      if Map.has_key?(pairs, t) or o in taken,
        do: {pairs, taken},
        else: {Map.put(pairs, t, o), MapSet.put(taken, o)}
    end)
    |> elem(0)
  end

  defp score(t, o, nil, _), do: name_similarity(t.name, o.name)
  defp score(t, o, _, nil), do: name_similarity(t.name, o.name)
  # A clear name match stands on its own; the profile only helps a weak one.
  defp score(t, o, tp, op) do
    name = name_similarity(t.name, o.name)
    max(name, (name + overlap(tp, op)) / 2)
  end

  defp name_similarity(a, b), do: String.jaro_distance(normalise(a), normalise(b))

  defp normalise(name) do
    (name || "")
    |> String.normalize(:nfd)
    |> String.replace(~r/[^\p{L} ]/u, "")
    |> String.downcase()
  end

  # How many speeches each character has in each twentieth of the play.
  defp profiles([]), do: %{}

  defp profiles(speeches) do
    n = length(speeches)

    for {speech, i} <- Enum.with_index(speeches), id <- speech.speakers, reduce: %{} do
      acc ->
        bucket = div(i * @buckets, n)
        Map.update(acc, id, %{bucket => 1}, &Map.update(&1, bucket, 1, fn c -> c + 1 end))
    end
  end

  # Where two characters speak (the cosine of their profiles), and, as a tie-breaker, how
  # much: a role with 8 speeches in a scene against one with 2 there scores lower. Only
  # half weight on the count, since translators cut speeches.
  defp overlap(a, b) do
    {na, nb} = {Enum.sum(Map.values(a)), Enum.sum(Map.values(b))}
    cosine(a, b) * (0.5 + 0.5 * min(na, nb) / max(na, nb))
  end

  defp cosine(a, b) do
    dot = Enum.sum(for {k, v} <- a, do: v * Map.get(b, k, 0))
    dot / (norm(a) * norm(b))
  end

  defp norm(v), do: :math.sqrt(Enum.sum(for {_, c} <- v, do: c * c))

  ## Speeches

  defp pair_speeches(originals, translations, characters) do
    # A translation's speaker becomes the original character it pairs with; an unpaired one
    # matches nothing.
    mapped = fn id -> Map.get(characters, id, {:unpaired, id}) end
    o = Enum.map(originals, &{&1.id, Enum.sort(&1.speakers)})
    t = Enum.map(translations, &{&1.id, &1.speakers |> Enum.map(mapped) |> Enum.sort()})

    o
    |> segments(t, originals, translations)
    |> Enum.flat_map(fn {os, ts} -> walk(diff(os, ts), os, ts, nil, []) end)
  end

  # The finest level at which both texts have the same divisions, in the same order.
  defp segments(o, t, originals, translations) do
    [&{&1.act, &1.scene}, & &1.act]
    |> Enum.find_value(fn key ->
      oc = o |> Enum.zip(originals) |> Enum.chunk_by(&key.(elem(&1, 1)))
      tc = t |> Enum.zip(translations) |> Enum.chunk_by(&key.(elem(&1, 1)))
      keys = fn chunks -> Enum.map(chunks, &key.(elem(hd(&1), 1))) end

      if keys.(oc) == keys.(tc),
        do:
          Enum.zip(
            Enum.map(oc, &Enum.map(&1, fn {x, _} -> x end)),
            Enum.map(tc, &Enum.map(&1, fn {x, _} -> x end))
          )
    end) || [{o, t}]
  end

  defp diff(os, ts),
    do: List.myers_difference(Enum.map(os, &elem(&1, 1)), Enum.map(ts, &elem(&1, 1)))

  defp walk([], _os, _ts, _last, acc), do: Enum.reverse(acc)

  defp walk([{:eq, xs} | rest], os, ts, _last, acc) do
    {o_here, os} = Enum.split(os, length(xs))
    {t_here, ts} = Enum.split(ts, length(xs))
    pairs = Enum.zip_with(t_here, o_here, fn {t, _}, {o, _} -> pair(t, o, :same) end)
    walk(rest, os, ts, List.last(o_here), Enum.reverse(pairs, acc))
  end

  # A deletion beside an insertion: different speakers in the same stretch, paired by
  # proportion through it.
  defp walk([{a, xs}, {b, ys} | rest], os, ts, _last, acc)
       when {a, b} in [{:del, :ins}, {:ins, :del}] do
    {dels, inss} = if a == :del, do: {xs, ys}, else: {ys, xs}
    {o_here, os} = Enum.split(os, length(dels))
    {t_here, ts} = Enum.split(ts, length(inss))
    m = length(o_here)

    pairs =
      t_here
      |> Enum.with_index()
      |> Enum.map(fn {{t, _}, i} ->
        {o, _} = Enum.at(o_here, counterpart(i, length(t_here), m))
        pair(t, o, :other)
      end)

    walk(rest, os, ts, List.last(o_here), Enum.reverse(pairs, acc))
  end

  defp walk([{:del, xs} | rest], os, ts, _last, acc) do
    {o_here, os} = Enum.split(os, length(xs))
    walk(rest, os, ts, List.last(o_here), acc)
  end

  # Speeches the original does not have: a split of the original speech before or after
  # them when it has the same speaker, else an addition, kept beside the speech before.
  defp walk([{:ins, xs} | rest], os, ts, last, acc) do
    {t_here, ts} = Enum.split(ts, length(xs))
    next = List.first(os)

    pairs =
      Enum.map(t_here, fn {t, speakers} ->
        cond do
          match?({_, ^speakers}, last) -> pair(t, elem(last, 0), :split)
          match?({_, ^speakers}, next) -> pair(t, elem(next, 0), :split)
          true -> pair(t, elem(last || next || {nil, nil}, 0), :added)
        end
      end)

    walk(rest, os, ts, last, Enum.reverse(pairs, acc))
  end

  defp pair(t, o, kind), do: %{id: t, original: o, kind: kind}

  # The index, among `m`, as far through them as `i` of `n` (sync_scroll.mjs's counterpart).
  defp counterpart(_i, n, _m) when n <= 1, do: 0
  defp counterpart(i, n, m), do: round(i * (m - 1) / (n - 1))
end
