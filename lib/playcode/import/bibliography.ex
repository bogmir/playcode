defmodule Playcode.Import.Bibliography do
  @moduledoc """
  The one-time move of the FileMaker bibliography into Playcode (S4). Spec: "Import" in
  docs/superpowers/specs/2026-10-07-s4-bibliography-design.md.

  `load/1` reads six tables. `plan/2` decides what to write: it reads the database but
  never writes. `apply_plan/2` writes the plan in one transaction.

  A play the import has written to before (a `filemaker` link, or its "import" row in the
  activity log, which outlives the links) is skipped whole, so a re-run picks up the plays
  added since without undoing a curator's edits or removals. An entry whose `filemaker_id`
  already exists is reused, which keeps a shared edition one entry, and a link a curator
  already made to it is skipped as `:already_linked`.
  """

  import Ecto.Query

  alias Playcode.ActivityLog
  alias Playcode.Bibliography.{Entry, Link}
  alias Playcode.Import.{FilemakerSync, FilemakerXml}
  alias Playcode.Repo

  @default_dir "doc/ctce_dades"

  @files [
    bib_links: "T12_ObraBibliografiaSelecta.xml",
    bib_records: "T12.1_BibliografiaSelecta.xml",
    edition_links: "T04_ObraModernaRecomendada.xml",
    editions: "T04.1_EdModerna.xml",
    cities: "T13.1_Ciudad.xml",
    publishers: "T13.2_Editorial.xml"
  ]

  # T12.12. A blank category is criticism that was never categorised (the project,
  # 2026-10-07).
  @categories %{"2" => "translation", "3" => "adaptation"}

  # T12.13 and T04.12 share their ids.
  @languages %{"1" => "es", "2" => "fr", "3" => "en", "4" => "it", "5" => "pt", "6" => "de"}

  # T12.11.
  @types %{
    "1" => "article",
    "2" => "book_section",
    "3" => "scholarly_edition",
    "4" => "book",
    "5" => "proceedings",
    "6" => "prologue",
    "7" => "festschrift",
    "8" => "electronic",
    "9" => "thesis",
    "10" => "collection"
  }

  # T04.11: 2 is a chapter; 1 and blank print as a book.
  @chapter "2"

  # T04.1 rows that are FileMaker's own tests, not editions.
  @test_editions ~w(9 147)

  @no_lookups %{cities: %{}, publishers: %{}}

  def default_dir, do: @default_dir

  @doc "Reads the six tables from `dir`."
  def load(dir) do
    Enum.reduce_while(@files, {:ok, %{}}, fn {key, file}, {:ok, data} ->
      case FilemakerXml.read(Path.join(dir, file)) do
        {:ok, rows} -> {:cont, {:ok, Map.put(data, key, rows)}}
        {:error, reason} -> {:halt, {:error, {file, reason}}}
      end
    end)
  end

  @doc "City and publisher names by id, from `T13.1` and `T13.2`."
  def lookups(data) do
    %{
      cities: lookup(data.cities, "_kp_IdCiudad", "Ciu_Ciudad"),
      publishers: lookup(data.publishers, "_kp_IdEditorial", "Edi_Editorial")
    }
  end

  @doc "What `apply_plan/2` would write. Reads the database, writes nothing. See the moduledoc."
  def plan(data, plays) do
    lookups = lookups(data)

    context = %{
      by_code: Enum.group_by(plays, &FilemakerSync.base_code(&1.code)),
      imported: imported_play_ids(),
      linked: linked_refs()
    }

    records = Map.new(data.bib_records, &{&1["_kp_IdBiblioSelecta"], &1})
    editions = editions_by_id(data.editions)

    bib = %{
      table: "T12",
      key: "_k_IdBiblioSelecta",
      rows: records,
      tests: [],
      attrs: &record_attrs(&1, lookups),
      link: &bib_link_attrs/1
    }

    eds = %{
      table: "T04",
      key: "_k_IdEdicionModerna",
      rows: editions,
      tests: @test_editions,
      attrs: &edition_attrs(&1, lookups),
      link: &edition_link_attrs/1
    }

    acc =
      %{
        entries: %{},
        links: [],
        seen: MapSet.new(),
        already_imported: MapSet.new(),
        skipped: %{},
        not_held: 0
      }
      |> walk(data.bib_links, bib, context)
      |> walk(data.edition_links, eds, context)
      |> skip_unlinked(bib, data.bib_links)
      |> skip_unlinked(eds, data.edition_links)

    %{
      entries: acc.entries,
      existing: existing_refs(Map.keys(acc.entries)),
      links: Enum.reverse(acc.links),
      already_imported: acc.already_imported |> MapSet.to_list() |> Enum.sort(),
      skipped: Map.new(acc.skipped, fn {reason, refs} -> {reason, Enum.reverse(refs)} end),
      not_held: acc.not_held
    }
  end

  @doc """
  Writes the plan in one transaction: the entries not yet in Playcode, then every link,
  then one activity-log entry per play. Returns `{:ok, %{entries: created, links: n}}`.
  """
  def apply_plan(plan, opts \\ []) do
    Repo.transaction(
      fn ->
        existing =
          Entry
          |> where([e], e.filemaker_id in ^Map.keys(plan.entries))
          |> select([e], {e.filemaker_id, e.id})
          |> Repo.all()
          |> Map.new()

        created =
          plan.entries
          |> Map.drop(Map.keys(existing))
          |> Map.new(fn {ref, attrs} -> {ref, insert_entry!(ref, attrs)} end)

        ids = Map.merge(existing, created)

        Enum.each(plan.links, fn link ->
          %Link{
            play_id: link.play_id,
            entry_id: Map.fetch!(ids, link.filemaker_id),
            origin: "filemaker"
          }
          |> Link.changeset(Map.take(link, [:volume, :pages, :note]))
          |> Repo.insert!()
        end)

        plan.links
        |> Enum.group_by(& &1.play_id)
        |> Enum.each(fn {play_id, links} ->
          ActivityLog.log!(%{
            user_id: opts[:user_id],
            play_id: play_id,
            action: "import",
            resource_type: "play_bibliography",
            resource_id: play_id,
            changes: %{"links" => length(links)},
            metadata: %{"source" => "filemaker"}
          })
        end)

        %{entries: map_size(created), links: length(plan.links)}
      end,
      timeout: :infinity
    )
  end

  defp insert_entry!(ref, attrs) do
    %Entry{filemaker_id: ref}
    |> Entry.changeset(attrs)
    |> Repo.insert!()
    |> Map.fetch!(:id)
  end

  @doc "The plan as lines of text, for the mix task and the release."
  def report(plan) do
    per_play =
      plan.links
      |> Enum.group_by(& &1.code)
      |> Enum.sort()
      |> Enum.map(fn {code, links} -> "#{code}  #{length(links)} links" end)

    totals =
      for {table, label} <- [{"T12", "bibliography"}, {"T04", "modern editions"}] do
        refs = plan.entries |> Map.keys() |> Enum.filter(&String.starts_with?(&1, table <> ":"))
        links = Enum.filter(plan.links, &String.starts_with?(&1.filemaker_id, table <> ":"))
        plays = links |> Enum.uniq_by(& &1.play_id) |> length()
        reused = Enum.count(refs, &(&1 in plan.existing))

        "#{label}: #{length(refs)} entries (#{reused} already in Playcode), " <>
          "#{length(links)} links on #{plays} plays"
      end

    skipped =
      for {reason, refs} <- Enum.sort(plan.skipped) do
        "skipped, #{reason}: #{length(refs)}  #{Enum.join(refs, ", ")}"
      end

    per_play ++
      [""] ++
      totals ++
      skipped ++
      [
        "already imported: #{length(plan.already_imported)} plays #{Enum.join(plan.already_imported, ", ")}",
        "links to versions not held: #{plan.not_held}"
      ]
  end

  @doc "A `T12.1` record as entry attributes."
  def record_attrs(row, lookups) do
    type = @types[value(row, "_k_IdBiblioSelTipo")]
    title = value(row, "BibSel_Titulo")

    # A book has no analytic level: FileMaker prints this field after the year, as a
    # series (49 of 51 books that have it).
    {analytic_title, series} = if type == "book", do: {nil, title}, else: {title, nil}

    %{
      kind: Map.get(@categories, value(row, "_k_IdBiblioSelCategoria"), "criticism"),
      pub_type: type,
      language: @languages[value(row, "_k_IdBiblioSelIdioma")],
      analytic_author: value(row, "BibSel_Autor"),
      analytic_title: analytic_title,
      analytic_editors: value(row, "BibSel_Editor"),
      analytic_translators: value(row, "BibSel_Traductor"),
      monogr_author: value(row, "BibSel_Autor2"),
      monogr_title: value(row, "BibSel_Titulo2"),
      monogr_editors: value(row, "BibSel_Editor2"),
      monogr_translators: value(row, "BibSel_Traductor2"),
      original_title: value(row, "BibSel_TituloOriginal"),
      edition: value(row, "BibSel_Edicion"),
      volume: value(row, "BibSel_NumVolTomo"),
      volumes_total: value(row, "BibSel_VolTomoTotal"),
      issue: value(row, "BibSel_Ejemplar"),
      pages: value(row, "BibSel_Pag"),
      year_text: value(row, "BibSel_Ano"),
      url: value(row, "BibSel_URL"),
      url_accessed_on: value(row, "BibSel_URL_FechaAcceso"),
      series: series,
      note: value(row, "BibSel_Nota")
    }
    |> Map.merge(place_and_publisher(row, lookups))
  end

  @doc """
  A `T04.1` edition as entry attributes. A chapter has two levels; a book only the
  monograph, and its second title is printed as a series. `EdiMod_VolTomo` is the
  edition's number of volumes; the play's own volume is on the link.
  """
  def edition_attrs(row, lookups) do
    chapter? = value(row, "_k_IdEdicionModernaTipo") == @chapter
    first = level(row, "")
    second = level(row, "2")

    levels =
      if chapter? do
        first
        |> prefixed("analytic")
        |> Map.merge(prefixed(second, "monogr"))
        |> Map.put(:series, value(row, "EdiMod_Titulo3"))
      else
        # A book's second-level people are never printed by FileMaker; only its second
        # title is, as the series.
        first
        |> prefixed("monogr")
        |> Map.put(:series, second.title || value(row, "EdiMod_Titulo3"))
      end

    %{
      kind: "modern_edition",
      pub_type: if(chapter?, do: "book_section", else: "book"),
      language: @languages[value(row, "_k_IdEdicionModernaIdioma")],
      edition: value(row, "EdiMod_Edicion"),
      pages: value(row, "EdiMod_Pag"),
      volumes_total: value(row, "EdiMod_VolTomo"),
      year_text: value(row, "EdiMod_Ano"),
      url: value(row, "EdiMod_URL"),
      url_accessed_on: value(row, "EdiMod_URL_FechaAcceso"),
      siglum: value(row, "EdiMod_Siglas"),
      public_note: value(row, "EdiMod_Nota"),
      # T04.1 has none of these: the play's volume is on the link, and EdiMod_Nota is printed.
      volume: nil,
      issue: nil,
      original_title: nil,
      note: nil
    }
    |> Map.merge(levels)
    |> Map.merge(place_and_publisher(row, lookups))
  end

  @doc "`T04.1` by id. Id 576 appears twice, one copy blank: the copy that names something wins."
  def editions_by_id(rows) do
    rows
    |> Enum.group_by(& &1["_kp_IdEdicionModerna"])
    |> Map.new(fn {id, [first | _] = copies} ->
      {id, Enum.find(copies, first, &Entry.named?(edition_attrs(&1, @no_lookups)))}
    end)
  end

  defp walk(acc, links, table, context) do
    Enum.reduce(links, acc, fn row, acc ->
      id = row[table.key] || ""
      ref = "#{table.table}:#{id}"

      cond do
        id == "" ->
          skip(acc, :no_record, "#{table.table} link to version #{row["_k_IdObraTitulo"]}")

        not Map.has_key?(table.rows, id) ->
          skip(acc, :missing_record, ref)

        id in table.tests ->
          skip(acc, :test_record, ref)

        true ->
          attrs = table.attrs.(table.rows[id])

          if Entry.named?(attrs),
            do: link_versions(acc, context, ref, attrs, row["_k_IdObraTitulo"], table.link.(row)),
            else: skip(acc, :no_name, ref)
      end
    end)
  end

  defp link_versions(acc, context, ref, attrs, version, link_attrs) do
    case Map.get(context.by_code, version_code(version), []) do
      [] ->
        %{acc | not_held: acc.not_held + 1}

      plays ->
        Enum.reduce(plays, acc, fn play, acc ->
          cond do
            MapSet.member?(context.imported, play.id) ->
              %{acc | already_imported: MapSet.put(acc.already_imported, play.code)}

            # A curator linked it already, from "Add existing" on a play imported later.
            MapSet.member?(context.linked, {play.id, ref}) ->
              skip(acc, :already_linked, "#{ref} on #{play.code}")

            MapSet.member?(acc.seen, {play.id, ref}) ->
              skip(acc, :duplicate_link, "#{ref} on #{play.code}")

            true ->
              link =
                Map.merge(link_attrs, %{play_id: play.id, code: play.code, filemaker_id: ref})

              %{
                acc
                | entries: Map.put(acc.entries, ref, attrs),
                  links: [link | acc.links],
                  seen: MapSet.put(acc.seen, {play.id, ref})
              }
          end
        end)
    end
  end

  defp skip_unlinked(acc, table, links) do
    linked = MapSet.new(links, & &1[table.key])

    table.rows
    |> Map.keys()
    |> Enum.reject(&MapSet.member?(linked, &1))
    |> Enum.sort()
    |> Enum.reduce(acc, &skip(&2, :unlinked, "#{table.table}:#{&1}"))
  end

  defp skip(acc, reason, ref),
    do: %{acc | skipped: Map.update(acc.skipped, reason, [ref], &[ref | &1])}

  # The play code FileMaker's version id stands for: 38 is EMOTHE0038.
  defp version_code(version) do
    case Integer.parse(version || "") do
      {number, ""} -> "EMOTHE" <> String.pad_leading(Integer.to_string(number), 4, "0")
      _other -> nil
    end
  end

  defp level(row, suffix) do
    %{
      author: value(row, "EdiMod_Autor" <> suffix),
      title: value(row, "EdiMod_Titulo" <> suffix),
      editors: value(row, "EdiMod_Editor" <> suffix),
      translators: value(row, "EdiMod_Traductor" <> suffix)
    }
  end

  defp prefixed(level, "analytic") do
    %{
      analytic_author: level.author,
      analytic_title: level.title,
      analytic_editors: level.editors,
      analytic_translators: level.translators
    }
  end

  defp prefixed(level, "monogr") do
    %{
      monogr_author: level.author,
      monogr_title: level.title,
      monogr_editors: level.editors,
      monogr_translators: level.translators
    }
  end

  # One publisher "key" in T12.1 is a name typed into the key field: a key that is not a
  # number is the name itself.
  defp place_and_publisher(row, lookups) do
    publisher = value(row, "_k_IdEditorial")

    %{
      pub_place: lookups.cities[value(row, "_k_IdCiudad")],
      publisher:
        if(publisher && publisher =~ ~r/^\d+$/,
          do: lookups.publishers[publisher],
          else: publisher
        )
    }
  end

  defp bib_link_attrs(row), do: %{note: value(row, "ObrBibSel_Nota"), volume: nil, pages: nil}

  defp edition_link_attrs(row),
    do: %{
      note: nil,
      volume: value(row, "ObraEdMod_Volumen"),
      pages: value(row, "ObraEdMod_Paginas")
    }

  defp lookup(rows, key, name), do: Map.new(rows, &{&1[key], value(&1, name)})

  defp value(row, field) do
    case row[field] do
      nil -> nil
      text -> if String.trim(text) == "", do: nil, else: String.trim(text)
    end
  end

  # A play is done once the import has written to it. Its filemaker links alone are no
  # marker: a curator may remove every one of them, and the next run must not bring them
  # back. The activity-log row apply_plan/2 writes per play survives that.
  defp imported_play_ids do
    logged =
      ActivityLog.Entry
      |> where([a], a.action == "import" and a.resource_type == "play_bibliography")
      |> select([a], a.play_id)

    Link
    |> where([l], l.origin == "filemaker")
    |> select([l], l.play_id)
    |> union(^logged)
    |> Repo.all()
    |> MapSet.new()
  end

  # `{play_id, filemaker_id}` for every link a play already has to an imported entry.
  defp linked_refs do
    Link
    |> join(:inner, [l], e in Entry, on: e.id == l.entry_id)
    |> where([_l, e], not is_nil(e.filemaker_id))
    |> select([l, e], {l.play_id, e.filemaker_id})
    |> Repo.all()
    |> MapSet.new()
  end

  defp existing_refs([]), do: []

  defp existing_refs(refs) do
    Entry
    |> where([e], e.filemaker_id in ^refs)
    |> select([e], e.filemaker_id)
    |> Repo.all()
  end
end
