defmodule Playcode.Export.StaticSite.Search do
  @moduledoc """
  Full-text search for the static site: the normaliser, and the writer of the index
  files. Both are read in the browser by `priv/static_site/search.js`.

  Files are JS that call `EMOTHE.search.load/3`, not JSON, because browsers refuse
  `fetch` on `file://` while a `<script>` tag still works there:

    * `search/plays.js` — the plays in index order;
    * `search/index/<shard>.js` — word → postings, sharded by the word's first two
      characters. Per play, `[play, n, d1 … dn]`: `d = (line - previous line) * 2 + flag`,
      previous starting at 0, flag 1 for a stage direction;
    * `search/lines/<CODE>/<k>.js` — lines `k * 100` to `k * 100 + 99` of one play, so a
      search loads only the lines it shows.

  `normalise/1` and `words/1` must agree with `EMOTHE.normalise` and `EMOTHE.words` in
  `site.js`; `test/fixtures/search_normalisation.json` runs against both.
  """

  alias Playcode.Catalogue.Play
  alias Playcode.Export.StaticSite
  alias Playcode.Export.StaticSite.{Components, Edition}
  alias Playcode.PlayContent.InlineMarkup

  @doc """
  Lowercase, accents dropped, `ñ` kept (so *año* and *ano* stay apart), NFC first so a
  decomposed `n` + tilde counts as `ñ`.
  """
  def normalise(nil), do: ""

  def normalise(text) do
    text
    |> :unicode.characters_to_nfc_binary()
    |> String.downcase(:greek)
    # U+E000 (private use) holds the ñ's place while the other accents are stripped.
    |> String.replace("ñ", "\u{E000}")
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.replace("\u{E000}", "ñ")
  end

  @doc "The searchable words of `text`: runs of letters and digits, normalised."
  def words(text), do: ~r/[\p{L}\p{N}]+/u |> Regex.scan(normalise(text)) |> List.flatten()

  @kinds %{verse: "v", prose: "p", stage: "s"}
  @lines_per_chunk 100

  @doc "Lines per `search/lines/<CODE>/<k>.js` file; `search.js` uses the same number."
  def lines_per_chunk, do: @lines_per_chunk

  @doc "The shard a word lives in: its first two characters (code points)."
  def shard_key(word), do: word |> String.codepoints() |> Enum.take(2) |> Enum.join()

  @doc "A shard key as a file name: `a-z` and `0-9` as they are, anything else as `u` + 4 hex digits."
  def shard_file(key) do
    key
    |> String.codepoints()
    |> Enum.map_join(fn char ->
      if char =~ ~r/\A[a-z0-9]\z/ do
        char
      else
        <<code::utf8>> = char
        "u" <> (code |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(4, "0"))
      end
    end)
  end

  @doc """
  Writes `search/lines/<CODE>/<k>.js` for one play and returns its postings, by shard key:
  one line per word, the word and then its `n,d1,…,dn` as the shard prints them after the
  play's number (`"sueño 2,6,9"`), lines ascending. A build holds every play's postings
  until it writes the index; as one string per shard they take about the index's own
  size, where a term per word (or per line) took several times it.
  """
  def write_play(dir, %Edition{} = edition) do
    code = StaticSite.safe_code!(edition.play.code)
    play_dir = Path.join([dir, "search", "lines", code])
    File.rm_rf!(play_dir)
    # Kept even with no lines: indexed_codes/1 reads a missing folder as an old index.
    File.mkdir_p!(play_dir)

    entries =
      for item <- edition.items, Map.has_key?(edition.page_of, item.element.id) do
        %{
          slug: edition.page_of[item.element.id],
          anchor: edition.anchors[item.element.id],
          ref: edition.refs[item.element.id],
          speaker: speaker(item),
          kind: @kinds[item.kind],
          text: InlineMarkup.plain(item.element.content),
          stage_only: stage_only_words(item.element.content)
        }
      end

    entries
    |> Enum.chunk_every(@lines_per_chunk)
    |> Enum.with_index()
    |> Enum.each(fn {chunk, k} ->
      speakers = chunk |> Enum.map(& &1.speaker) |> Enum.reject(&is_nil/1) |> Enum.uniq()
      index_of = speakers |> Enum.with_index() |> Map.new()

      lines =
        Enum.map(chunk, &[&1.slug, &1.anchor, &1.ref, index_of[&1.speaker], &1.kind, &1.text])

      write_js!(Path.join(play_dir, "#{k}.js"), "lines", "#{code}/#{k}", %{
        "speakers" => speakers,
        "lines" => lines
      })
    end)

    entries
    |> Enum.with_index()
    |> Enum.flat_map(fn {entry, line} ->
      stage_line? = entry.kind == "s"

      entry.text
      |> words()
      |> Enum.uniq()
      |> Enum.map(fn word ->
        {word, {line, if(stage_line? or word in entry.stage_only, do: 1, else: 0)}}
      end)
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.group_by(fn {word, _lines} -> shard_key(word) end)
    |> Map.new(fn {key, words} ->
      {key,
       Enum.map_join(words, "\n", fn {word, lines} -> word <> " " <> group(deltas(lines)) end)}
    end)
  end

  # The words of a line that occur in its inline stage directions and nowhere in what is
  # spoken: those, and no others, are stage direction hits. Most lines hold no stage.
  defp stage_only_words(content) do
    if is_binary(content) and String.contains?(content, "</stage>") do
      spoken = content |> InlineMarkup.spoken() |> words() |> MapSet.new()
      content |> InlineMarkup.staged() |> words() |> Enum.reject(&MapSet.member?(spoken, &1))
    else
      []
    end
  end

  # One play's postings for one word as a shard prints them: `n, d1 … dn`.
  defp group(deltas), do: Enum.map_join([length(deltas) | deltas], ",", &Integer.to_string/1)

  defp speaker(%{speakers: []}), do: nil
  defp speaker(%{speakers: speakers}), do: Enum.map_join(speakers, " / ", &elem(&1, 1))

  @doc """
  Writes `search/plays.js` and every shard for `plays`, in that order. `postings` maps a
  play's code to what `write_play/2` returned for it; a play in `plays` that `postings`
  lacks keeps the postings the site's current shards hold for it, under its new index, so
  adding or removing one play reloads no other. Removes the lines files of plays no longer
  in `plays`. Returns the total and the largest shard size.

  Shards are written one at a time, each old one read only when its turn comes, so what
  the index needs in memory beyond `postings` is one shard.
  """
  def write_index(dir, plays, postings) do
    order = plays |> Enum.with_index() |> Map.new(fn {play, p} -> {play.code, p} end)

    # Read before plays.js is rewritten: it maps the old shards' play numbers to codes.
    remap = remap(dir, order, postings)

    write_js!(
      Path.join([dir, "search", "plays.js"]),
      "plays",
      "all",
      Enum.map(plays, &play_entry/1)
    )

    prune_lines(dir, plays)

    fresh = for {code, by_key} <- postings, p when not is_nil(p) <- [order[code]], do: {p, by_key}
    write_shards(Path.join([dir, "search", "index"]), remap, fresh)
  end

  @doc """
  Codes of the plays the site's current index holds, in index order. Empty when the index
  predates chunked lines (an old flat `search/lines/<CODE>.js` remains, or some play has
  no `search/lines/<CODE>/` folder): its shards are in another format and must not be
  carried over. The flat files go only once the new index is written, so a run that
  crashed half way is still read as old.
  """
  def indexed_codes(dir) do
    with [] <- Path.wildcard(Path.join([dir, "search", "lines", "*.js"])),
         {:ok, _key, plays} <- read_js(Path.join([dir, "search", "plays.js"])),
         codes = Enum.map(plays, & &1["code"]),
         true <- Enum.all?(codes, &File.dir?(Path.join([dir, "search", "lines", &1]))) do
      codes
    else
      _ -> []
    end
  end

  # The current index's play numbers, each to its number in the new one: a play's deltas
  # do not change when its number does. Plays that left the site, and plays whose
  # postings were just recomputed, map to nil and are dropped. Empty when there is no
  # current index to carry from.
  defp remap(dir, order, postings) do
    dir
    |> indexed_codes()
    |> Enum.with_index()
    |> Map.new(fn {code, old} ->
      {old, if(Map.has_key?(postings, code), do: nil, else: order[code])}
    end)
  end

  defp play_groups([]), do: []

  defp play_groups([play, n | rest]) do
    {deltas, rest} = Enum.split(rest, n)
    [{play, deltas} | play_groups(rest)]
  end

  defp read_js(path) do
    with {:ok, js} <- File.read(path),
         [_, key, json] <-
           Regex.run(~r/\AEMOTHE\.search\.load\(".*?",(".*?"),(.*)\);\n\z/s, js) do
      {:ok, Jason.decode!(key), Jason.decode!(json)}
    else
      _ -> :error
    end
  end

  # Each shard goes to a hidden folder that replaces the index once all are written: a
  # current shard's words, its carried plays renumbered by `remap`, plus the `fresh`
  # postings under its key. A shard left with no play is not written. `fresh` holds each
  # play's number and its postings by shard key, as write_play/2 returns them.
  defp write_shards(index_dir, remap, fresh) do
    new_dir = Path.join(Path.dirname(index_dir), ".index.new")
    File.rm_rf!(new_dir)
    File.mkdir_p!(new_dir)

    current = if remap == %{}, do: [], else: Path.wildcard(Path.join(index_dir, "*.js"))

    {carried_sizes, written} =
      Enum.flat_map_reduce(current, MapSet.new(), fn path, written ->
        case read_js(path) do
          {:ok, key, shard} ->
            carried =
              for {word, list} <- shard,
                  {old, deltas} <- play_groups(list),
                  new when not is_nil(new) <- [remap[old]],
                  do: {word, new, group(deltas)}

            {write_shard(new_dir, key, carried ++ fresh_words(fresh, key)),
             MapSet.put(written, key)}

          # Unreadable: nothing to carry from it.
          :error ->
            {[], written}
        end
      end)

    unwritten =
      for {_p, by_key} <- fresh,
          key <- Map.keys(by_key),
          not MapSet.member?(written, key),
          into: MapSet.new(),
          do: key

    sizes =
      carried_sizes ++
        Enum.flat_map(unwritten, &write_shard(new_dir, &1, fresh_words(fresh, &1)))

    File.rm_rf!(index_dir)
    File.rename!(new_dir, index_dir)
    %{index_bytes: Enum.sum(sizes), largest_shard_bytes: Enum.max(sizes, fn -> 0 end)}
  end

  # The fresh postings under one shard key, as `{word, play, group}`.
  defp fresh_words(fresh, key) do
    for {p, by_key} <- fresh,
        text when is_binary(text) <- [by_key[key]],
        line <- String.split(text, "\n"),
        [word, group] = String.split(line, " ", parts: 2),
        do: {word, p, group}
  end

  # One shard file; returns its size in a list, empty when the shard has no word.
  defp write_shard(_dir, _key, []), do: []

  defp write_shard(dir, key, words) do
    data =
      words
      |> Enum.group_by(&elem(&1, 0), &{elem(&1, 1), elem(&1, 2)})
      |> Map.new(fn {word, groups} ->
        {word,
         groups |> Enum.sort() |> Enum.flat_map(fn {p, g} -> [p, Jason.Fragment.new(g)] end)}
      end)

    [write_js!(Path.join(dir, shard_file(key) <> ".js"), "index", key, data)]
  end

  defp deltas(lines) do
    {deltas, _last} =
      Enum.map_reduce(lines, 0, fn {line, flag}, previous ->
        {(line - previous) * 2 + flag, line}
      end)

    deltas
  end

  # Anything under search/lines/ that is not the folder of a play in the site: a removed
  # play, or a lines file written by an older build.
  defp prune_lines(dir, plays) do
    lines_dir = Path.join([dir, "search", "lines"])
    keep = MapSet.new(plays, & &1.code)

    case File.ls(lines_dir) do
      {:ok, entries} ->
        for entry <- entries,
            not MapSet.member?(keep, entry),
            do: File.rm_rf!(Path.join(lines_dir, entry))

      {:error, _} ->
        :ok
    end
  end

  defp play_entry(play) do
    %{
      "code" => play.code,
      "title" => play.title,
      "author" => play.author_name,
      "language" => play.language,
      "language_name" => Play.language_name(play.language),
      "kind" => Components.kind(play)
    }
  end

  defp write_js!(path, kind, key, data) do
    File.mkdir_p!(Path.dirname(path))

    js = [
      "EMOTHE.search.load(",
      Jason.encode!(kind),
      ",",
      Jason.encode!(key),
      ",",
      Jason.encode!(data, escape: :javascript_safe),
      ");\n"
    ]

    File.write!(path, js)
    IO.iodata_length(js)
  end
end
