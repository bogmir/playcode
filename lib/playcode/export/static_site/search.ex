defmodule Playcode.Export.StaticSite.Search do
  @moduledoc """
  Full-text search for the static site: the normaliser here, the index files from
  Task 8 on. Both are read in the browser by `priv/static_site/search.js`.

  `normalise/1` and `words/1` must agree with `EMOTHE.normalise` and `EMOTHE.words` in
  `site.js`; `test/fixtures/search_normalisation.json` runs against both.
  """

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
end
