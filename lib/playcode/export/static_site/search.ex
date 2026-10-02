defmodule Playcode.Export.StaticSite.Search do
  @moduledoc """
  Full-text search for the static site: the normaliser, and the writer of the index
  files. Both are read in the browser by `priv/static_site/search.js`.

  Files are JS that call `EMOTHE.search.load/3`, not JSON, because browsers refuse
  `fetch` on `file://` while a `<script>` tag still works there.

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
  Writes `search/lines/<CODE>.js` for one play and returns its postings:
  `%{word => [play_index, line_index, kind_flag, ...]}`, flat triples.
  """
  def write_play(dir, %Edition{} = edition, play_index) do
    entries =
      for item <- edition.items, Map.has_key?(edition.page_of, item.element.id) do
        %{
          slug: edition.page_of[item.element.id],
          anchor: edition.anchors[item.element.id],
          ref: edition.refs[item.element.id],
          speaker: speaker(item),
          kind: @kinds[item.kind],
          text: InlineMarkup.plain(item.element.content)
        }
      end

    speakers = entries |> Enum.map(& &1.speaker) |> Enum.reject(&is_nil/1) |> Enum.uniq()
    index_of = speakers |> Enum.with_index() |> Map.new()

    lines =
      Enum.map(entries, &[&1.slug, &1.anchor, &1.ref, index_of[&1.speaker], &1.kind, &1.text])

    write_js!(
      Path.join([dir, "search", "lines", "#{StaticSite.safe_code!(edition.play.code)}.js"]),
      "lines",
      edition.play.code,
      %{"speakers" => speakers, "lines" => lines}
    )

    entries
    |> Enum.with_index()
    |> Enum.flat_map(fn {entry, line} ->
      flag = if entry.kind == "s", do: 1, else: 0
      entry.text |> words() |> Enum.uniq() |> Enum.map(&{&1, [play_index, line, flag]})
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {word, postings} -> {word, List.flatten(postings)} end)
  end

  defp speaker(%{speakers: []}), do: nil
  defp speaker(%{speakers: speakers}), do: Enum.map_join(speakers, " / ", &elem(&1, 1))

  @doc """
  Writes `search/plays.js` and every `search/index/<shard>.js` from the postings of all
  plays, given in the order of `plays`. Returns the total and the largest shard size.
  """
  def write_index(dir, plays, postings) do
    write_js!(
      Path.join([dir, "search", "plays.js"]),
      "plays",
      "all",
      Enum.map(plays, &play_entry/1)
    )

    index_dir = Path.join([dir, "search", "index"])
    File.rm_rf!(index_dir)
    File.mkdir_p!(index_dir)

    sizes =
      postings
      |> Enum.reduce(%{}, &Map.merge(&2, &1, fn _word, earlier, later -> earlier ++ later end))
      |> Enum.group_by(fn {word, _postings} -> shard_key(word) end)
      |> Enum.map(fn {key, words} ->
        write_js!(Path.join(index_dir, shard_file(key) <> ".js"), "index", key, Map.new(words))
      end)

    %{index_bytes: Enum.sum(sizes), largest_shard_bytes: Enum.max(sizes, fn -> 0 end)}
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
