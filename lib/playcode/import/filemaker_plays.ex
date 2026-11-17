defmodule Playcode.Import.FilemakerPlays do
  @moduledoc """
  The one-time move of FileMaker's records Playcode does not hold into Playcode, as draft
  plays without a text. Spec: section 7.6 of
  docs/superpowers/specs/2026-11-17-plays-without-text-and-record-search-design.md, as
  the plan `2026-11-17-filemaker-plays-without-text.md` revised it on reading FileMaker's
  2026-11-17 export of `T01_ObraTitulo` and `T00_ObraIndice`.

  `load/2` reads the two tables. `plan/2` decides, writing nothing: a record becomes a
  play when no play, archived ones included, holds its code (`Play.short_code/1`). The
  edition state does not decide; the report prints it. Skipped and named: FileMaker's
  test records (their work's title starts "zzz"), and records with no title, no work or
  no language. Playcode is the source of truth: a record whose code it holds is left
  alone, and so is one whose file name is a code it holds under another number.

  A play is created with its kind (`_k_IdObraTipo`) and, unless it is an original, its
  work's main record (`T00._k_IdObraTituloPrincipal`) as its original when Playcode holds
  that play or this run creates it: `Catalogue.create_play/2` links the two, whichever
  arrives first. The text, when FileMaker holds one, comes through the TEI import
  (`write_texts/2`), which keeps both.
  """

  alias Playcode.Catalogue.Play
  alias Playcode.Import.{Filemaker, FilemakerXml}

  @default_dir "doc/ctce_dades"
  @titles "T01_ObraTitulo.xml"
  @works "T00_ObraIndice.xml"

  @fields ~w(_kp_IdObraTitulo _k_IdEstadoEdicion _k_IdObraTipo _k_IdIdioma _k_IdObraIndice
             w3em_pubTitulo w3em_pubTituloOrden w3em_pubAutor w3em_busTiempoHistorico
             w3em_pubTiemHistorico w3em_pubDatacion w3em_nombreArchivo)

  # Checked against 387 held plays, 2026-11-17: two disagree.
  @languages %{"1" => "es", "2" => "fr", "3" => "en", "4" => "it", "5" => "pt"}

  # T01.1. "Original no principal" is a later version (question 40).
  @kinds %{"0" => "version", "2" => "traduccion", "3" => "adaptacion"}

  # T01.3
  @states %{"0" => "sin texto", "1" => "en curso", "2" => "finalizada", "3" => "publicada"}

  def default_dir, do: @default_dir

  @doc "Reads `T01` (with its TEI text under `texts: true`) and `T00` from `dir`."
  def load(dir, opts \\ []) do
    fields = if opts[:texts], do: ["Tei_ObrTit" | @fields], else: @fields

    with {:ok, titles} <- read(dir, @titles, fields),
         {:ok, works} <- read(dir, @works, nil) do
      {:ok, %{titles: titles, works: works}}
    end
  end

  defp read(dir, file, fields) do
    case FilemakerXml.read(Path.join(dir, file), fields) do
      {:ok, rows} -> {:ok, rows}
      {:error, reason} -> {:error, {file, reason}}
    end
  end

  @doc "What `apply_plan/1` would create, and what it leaves. Writes nothing. See the moduledoc."
  def plan(data, plays) do
    held = MapSet.new(plays, &Play.short_code(&1.code))
    works = Map.new(data.works, &{&1["_kp_IdObraIndice"], &1})

    {create, skipped} =
      data.titles
      |> Enum.map(&{FilemakerXml.version_code(&1["_kp_IdObraTitulo"]), &1})
      |> Enum.reject(fn {code, _row} -> code in held end)
      |> Enum.map(fn {code, row} -> {code, row, skip_reason(code, row, works, held)} end)
      |> Enum.split_with(fn {_code, _row, reason} -> is_nil(reason) end)

    creating = MapSet.new(create, &elem(&1, 0))

    live =
      for play <- plays, is_nil(play.deleted_at), into: creating, do: Play.short_code(play.code)

    %{
      create:
        create
        |> Enum.map(fn {code, row, nil} -> play(code, row, original(code, row, works, live)) end)
        |> Enum.sort_by(& &1.attrs["code"]),
      held: length(data.titles) - length(create) - length(skipped),
      skipped:
        skipped
        |> Enum.map(fn {code, row, reason} ->
          %{code: code, title: title(row), reason: reason}
        end)
        |> Enum.sort_by(& &1.code)
    }
  end

  defp skip_reason(code, row, works, held) do
    work = works[row["_k_IdObraIndice"]]

    cond do
      is_nil(code) -> :no_code
      test?(row["w3em_pubTitulo"]) or test?(work["_w3em_tituloOrden"]) -> :test
      Play.short_code(file_code(row)) in held -> :held_under_file_name
      # "El " alone, the article of a title never typed
      String.length(title(row) || "") < 3 -> :no_title
      is_nil(work) -> :no_work
      is_nil(@languages[row["_k_IdIdioma"]]) -> :no_language
      true -> nil
    end
  end

  defp test?(title), do: String.starts_with?(String.downcase(title || ""), "zzz")

  defp play(code, row, original) do
    attrs =
      %{
        "code" => code(code, row),
        "title" => title(row),
        "title_sort" => blank(row["w3em_pubTituloOrden"]),
        "author_sort" => author_sort(row),
        "author_name" => author_name(author_sort(row)),
        "language" => @languages[row["_k_IdIdioma"]],
        "relationship_type" => @kinds[row["_k_IdObraTipo"]],
        "historical_time" => Filemaker.historical_time(row["w3em_busTiempoHistorico"]),
        "historical_time_note" => Filemaker.historical_time_note(row["w3em_pubTiemHistorico"]),
        "composition_date_note" => Filemaker.composition_date_note(row["w3em_pubDatacion"])
      }
      |> Map.reject(fn {_key, value} -> is_nil(value) end)

    %{
      attrs: attrs,
      original: original,
      state: @states[row["_k_IdEstadoEdicion"]],
      text: row["Tei_ObrTit"]
    }
  end

  # FileMaker's file name, an HIE file's as EMOTHE, when it is the record's and a code; its
  # number otherwise. A file whose code differs, `EMOTHE0283_…` for 627, is a clash.
  defp code(code, row) do
    file_code = file_code(row)

    if Play.short_code(file_code) == code and file_code =~ Play.code_format(),
      do: file_code,
      else: code
  end

  defp file_code(row), do: String.replace_prefix(row["w3em_nombreArchivo"] || "", "HIE", "EMOTHE")

  defp original(code, row, works, live) do
    main = FilemakerXml.version_code(works[row["_k_IdObraIndice"]]["_k_IdObraTituloPrincipal"])

    if @kinds[row["_k_IdObraTipo"]] && main != code && main in live, do: main
  end

  defp title(row), do: blank(row["w3em_pubTitulo"])

  # ", [Anonymous]": a surname never typed
  defp author_sort(row), do: blank(String.trim_leading(row["w3em_pubAutor"] || "", ", "))

  # ponytail: turned at the first comma; "Molière, (Jean-Baptiste Poquelin)" comes out
  # backwards, for a curator to correct
  defp author_name(nil), do: nil

  defp author_name(sort) do
    case String.split(sort, ",", parts: 2) do
      [surname, names] -> String.trim(names) <> " " <> String.trim(surname)
      [name] -> name
    end
  end

  defp blank(value) do
    case String.trim(value || "") do
      "" -> nil
      text -> text
    end
  end
end
