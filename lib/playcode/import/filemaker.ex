defmodule Playcode.Import.Filemaker do
  @moduledoc """
  Reads the FileMaker NDJSON export.

  The file holds two tables, each preceded by a `_meta` envelope line and followed by
  an `_end` line. Only `T00_indiceEM` — the published index — is read here: its
  `pub_listaObras` field is the rendered HTML of every published version of a work,
  and it is the authoritative source for a play's language, its family, and whether
  it is an original (credited `ed.`) or a translation (credited `tra.`).
  """

  @default_path "doc/w3emothe_T01_tituloEM.ndjson"
  @index_layout "T00_indiceEM"

  # <li>[EN] <a href="textosEMOTHE/CODE_File.php">TITLE</a> credit… [xml] </li>
  @version ~r|<li>(?:<span[^>]*>\[([A-Z]{2})\]\s*</span>)?\s*<a href="textosEMOTHE/([A-Za-z0-9]+)_([^"]*)\.php"[^>]*>(.*?)</a>(.*?)</li>|s

  @languages %{"ES" => "es", "EN" => "en", "FR" => "fr", "IT" => "it", "PT" => "pt"}

  @versions_layout "T01_tituloEM"

  # bus_tiemHistorico. Codes 3 and 4 do not occur anywhere in the export.
  @historical_times %{
    "1" => "tiempo_indeterminado",
    "2" => "antiguo_testamento",
    "5" => "edad_media",
    "6" => "siglo_xv",
    "7" => "siglo_xvi",
    "8" => "siglo_xvii",
    "9" => "tiempo_maravilloso",
    "10" => "antiguedad_clasica",
    "11" => "tiempo_alegorico"
  }

  # <a href='../biblioteca/textosEMOTHE/EMOTHE0038_AntonyAndCleopatra.php' …>
  @web_edition ~r|textosEMOTHE/([A-Za-z0-9]+)_|

  # The work header: <div><i>TITLE</i>. Author<span …>=1606 - =1607</span></div>. The
  # sigils (= ≥ ≤ ≈ ?) are qualifiers we deliberately do not model — the years are what
  # we store, and the string itself becomes the note.
  @work_dating ~r|<div>.*?<span[^>]*>([^<]*)</span>\s*</div>|s
  @four_digit_year ~r|\b(1[0-9]{3})\b|

  # Wider than this is a data-entry error in the export, not a dating: the widest real
  # header is 13 years (=1612 - =1625). Skipped rather than reported as a conflict,
  # because a conflict is tickable in /admin/filemaker and a force-write of a bad span
  # is precisely what this guard exists to prevent.
  @max_composition_span 40

  # <li>Antigüedad clásica<br/>Note: First century BC.…</li> — one item of a rendered
  # list. Used with Regex.run for the first item and Regex.scan for all of them.
  @list_item ~r|<li>(.*?)</li>|s

  def default_path, do: @default_path

  @doc """
  Returns `{:ok, %{code => version}}` for every published version in the index, or
  `{:error, reason}`: the file's, or `{:malformed_record, record_id}` for a record that
  cannot be read, which refuses the whole export rather than sync part of it.
  """
  def load_index(path \\ @default_path) do
    with {:ok, body} <- File.read(path),
         {:ok, {_layout, index}} <- read_records(body, &read_line/2) do
      {:ok, index}
    end
  end

  @doc """
  Returns `{:ok, %{code => version}}` for every version record in the export.

  The version records carry the research metadata that has no home in TEI. Only the
  fields S2a needs are read; later slices add to the map this returns.
  """
  def load_versions(path \\ @default_path) do
    with {:ok, body} <- File.read(path),
         {:ok, {_layout, versions}} <- read_records(body, &read_version_line/2) do
      {:ok, versions}
    end
  end

  # Folds `fun` over the file's lines from `{layout, %{}}`. `fun` returns the next
  # accumulator, or an error that stops the fold.
  defp read_records(body, fun) do
    body
    |> String.split("\n", trim: true)
    |> Enum.reduce_while({:ok, {nil, %{}}}, fn line, {:ok, acc} ->
      case fun.(line, acc) do
        {:error, _reason} = error -> {:halt, error}
        acc -> {:cont, {:ok, acc}}
      end
    end)
  end

  defp read_version_line(line, {layout, versions}) do
    case Jason.decode(line) do
      {:ok, %{"_meta" => meta}} ->
        {meta["layout"], versions}

      {:ok, %{"fields" => fields} = record} when layout == @versions_layout ->
        case is_map(fields) && version_code(fields) do
          code when is_binary(code) ->
            {layout, Map.put(versions, code, build_version(fields, code))}

          _ ->
            {:error, {:malformed_record, record["record_id"]}}
        end

      _ ->
        {layout, versions}
    end
  end

  defp build_version(fields, code) do
    %{
      code: code,
      historical_time: historical_time(fields),
      historical_time_note: historical_time_note(fields),
      composition_date_note: composition_date_note(fields)
    }
  end

  # The href is the only place the HIE#### codes appear; the numeric id is the fallback.
  # Nil when the record has neither.
  defp version_code(fields) do
    with nil <- Regex.run(@web_edition, field(fields, "pub_edicionWeb")),
         {id, ""} <- Integer.parse(field(fields, "_IdTituloEmothe")) do
      "EMOTHE" <> String.pad_leading(Integer.to_string(id), 4, "0")
    else
      [_all, code] -> code
      _no_id -> nil
    end
  end

  defp historical_time(fields) do
    fields
    |> field("bus_tiemHistorico")
    |> String.split("\n", trim: true)
    |> List.first()
    |> then(&Map.get(@historical_times, &1))
  end

  defp historical_time_note(fields) do
    with [_all, item] <- Regex.run(@list_item, field(fields, "pub_TiemHistorico")),
         [_label, note] <- String.split(item, ~r|<br\s*/?>\s*Note:|, parts: 2) do
      case strip_tags(note) do
        "" -> nil
        text -> text
      end
    else
      _ -> nil
    end
  end

  # Every <li> is a *competing* dating, unattributed. All of them verbatim, so a curator
  # reads the disagreement; the years come from the index header, which carries the
  # accepted dating rather than the union of the competing ones.
  defp composition_date_note(fields) do
    @list_item
    |> Regex.scan(field(fields, "pub_datacion"))
    |> Enum.map(fn [_all, item] -> strip_tags(item) end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("; ")
    |> case do
      "" -> nil
      note -> note
    end
  end

  defp read_line(line, {layout, index}) do
    case Jason.decode(line) do
      {:ok, %{"_meta" => meta}} ->
        {meta["layout"], index}

      {:ok, %{"fields" => fields}} when layout == @index_layout and is_map(fields) ->
        {layout, add_work(index, fields)}

      {:ok, %{"fields" => _not_a_record} = record} when layout == @index_layout ->
        {:error, {:malformed_record, record["record_id"]}}

      _ ->
        {layout, index}
    end
  end

  defp add_work(index, fields) do
    html = field(fields, "pub_listaObras")
    versions = parse_versions(html)
    family = Enum.map(versions, &Map.take(&1, [:code, :role]))
    dating = parse_dating(html)

    Enum.reduce(versions, index, fn version, acc ->
      version =
        version
        |> Map.put(:family, family)
        |> Map.merge(dating_for(version, dating))

      Map.put(acc, version.code, version)
    end)
  end

  # The header dating belongs to the *work*, so it is the composition date of the
  # original. A translation was composed centuries later and the export does not say
  # when, so it gets nothing. A work with no `ed.` version gets nothing anywhere: we
  # cannot tell whose composition it is.
  defp dating_for(%{role: :editor}, dating), do: dating
  defp dating_for(_version, _dating), do: %{}

  defp parse_dating(html) do
    case Regex.run(@work_dating, html) do
      [_all, text] -> dating_from(String.trim(text))
      _ -> %{}
    end
  end

  defp dating_from(""), do: %{}

  defp dating_from(text) do
    years =
      @four_digit_year
      |> Regex.scan(text)
      |> Enum.map(fn [_all, year] -> String.to_integer(year) end)

    case years do
      [] ->
        %{composition_date_skipped: {:unparseable, text}}

      years ->
        from = Enum.min(years)
        to = Enum.max(years)

        if to - from > @max_composition_span do
          %{composition_date_skipped: {:span, text}}
        else
          %{
            composition_date_from: from,
            composition_date_to: to,
            composition_date_note: text
          }
        end
    end
  end

  defp parse_versions(html) do
    @version
    |> Regex.scan(html)
    |> Enum.map(fn [_all, lang, code, _file, _title, rest] ->
      credit = rest |> strip_tags() |> String.replace("[xml]", "") |> String.trim()

      %{code: code, lang: Map.get(@languages, lang, ""), role: role(credit)}
    end)
  end

  defp role(credit) do
    cond do
      Regex.match?(~r{,\s*ed\.}, credit) -> :editor
      Regex.match?(~r{,\s*tra\.}, credit) -> :translator
      true -> nil
    end
  end

  defp strip_tags(html) do
    html
    |> String.replace(~r{<[^>]+>}, " ")
    |> String.replace(~r{\s+}, " ")
    |> String.trim()
  end

  defp field(fields, key) do
    case Map.get(fields, key) do
      list when is_list(list) -> list |> Enum.join("\n") |> String.trim()
      value when is_binary(value) -> String.trim(value)
      _ -> ""
    end
  end
end
