defmodule Playcode.Import.TeiImport do
  @moduledoc """
  Imports a TEI-XML file: `Playcode.Import.TeiParser` reads it, this module writes what
  it read, in one transaction.

  A re-import updates the play with that code in place. It replaces the play's whole
  text and the editors, sources, paratexts, witnesses, place links and performances the
  importer created itself (`origin: "tei"`); everything a researcher typed is kept, and so
  are the columns the platform owns. `preview_import/1` reports that before anything is written.
  """

  import Ecto.Query

  alias Playcode.Bibliography
  alias Playcode.Bibliography.{Citation, Entry, Link}
  alias Playcode.Catalogue
  alias Playcode.Catalogue.{Play, PlayEditor, PlaySource, Paratext}
  alias Playcode.Import.TeiParser
  alias Playcode.Performances
  alias Playcode.Performances.Performance
  alias Playcode.PlayContent
  alias Playcode.PlayContent.{Character, Division, Element, ElementCharacter, Note}
  alias Playcode.Places
  alias Playcode.Repo
  alias Playcode.Text
  alias Playcode.Witnesses
  alias Playcode.Witnesses.Witness

  require Logger

  # Columns the platform owns, not the TEI file. `language` in particular: every EMOTHE
  # file carries xml:lang="es" for the editorial platform, so a re-import would undo the
  # FileMaker sync (docs/superpowers/plans/2026-08-01-s1-work-families-and-language.md).
  # New research columns added by later slices belong on this list.
  @platform_owned [
    :language,
    :relationship_type,
    :parent_play_id,
    :is_complete,
    :show_variants,
    :historical_time,
    :historical_time_note,
    :composition_date_from,
    :composition_date_to,
    :composition_date_note,
    :form
  ]

  @doc "The `Play` columns a re-import keeps: the ones the platform owns, not the TEI file."
  def platform_owned, do: @platform_owned

  @doc """
  Imports a TEI-XML file from the given path into the database.
  Returns {:ok, play} or {:error, reason}.
  """
  def import_file(path) do
    Logger.info("Importing TEI file: #{path}")

    case TeiParser.parse_file(path) do
      {:ok, tei} ->
        fn -> write(tei) end
        |> Repo.transaction()
        |> Catalogue.link_waiting_translations()

      {:error, reason} ->
        Logger.error("Import failed for #{path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Reports what importing `path` would do, without writing anything.

  A re-import replaces the play's whole text and the editors, sources and paratexts the
  importer created itself; everything a researcher typed is kept, as are the columns
  the platform owns. This is what the admin import page and `--dry-run` print so that
  nobody discovers the replacement afterwards.
  """
  def preview_import(path) do
    with {:ok, tei} <- TeiParser.parse_file(path), do: {:ok, preview(tei)}
  end

  defp preview(%{play: %{code: code, title: title}} = tei) do
    existing = Repo.get_by(Play, code: code)

    %{
      code: code,
      title: title,
      existing: existing,
      archived: not is_nil(existing) and not is_nil(existing.deleted_at),
      replaces: replaced_counts(existing),
      edited: edited_count(existing),
      preserves: preserved_counts(existing),
      preserves_fields: preserved_fields(existing)
    }
    |> Map.merge(bibliography_preview(tei.bibliography, existing))
  end

  # The import's bibliography plan as it prints: the references the play would gain, and
  # those it would skip. A stale one, an older file's version of a reference corrected
  # since, shows among the first before it is imported.
  defp bibliography_preview(references, existing) do
    steps = bibliography_plan(references, existing && existing.id)

    %{
      bibliography_adds: for({step, _, ref} <- steps, step != :skip, do: citation(ref)),
      bibliography_skips: for({:skip, _, ref} <- steps, do: citation(ref))
    }
  end

  defp citation(reference) do
    Citation.plain(
      struct(Entry, reference.description),
      %Link{volume: reference.volume, pages: reference.pages}
    )
  end

  @doc """
  Sums the mixed-ownership counts in one half of a `preview_import/1` result.

  Those six tables — editors, sources, paratexts, places, witnesses and performances — hold
  both TEI-imported and hand-entered rows, so `:replaces` and `:preserves` split each one by
  `origin`. Both the admin import page and the `--dry-run` output report the totals, and
  adding a seventh such table must not mean remembering two more addition sites.
  """
  def mixed_ownership_total(counts) do
    [:editors, :sources, :paratexts, :places, :witnesses, :performances]
    |> Enum.map(&Map.fetch!(counts, &1))
    |> Enum.sum()
  end

  defp replaced_counts(nil),
    do: %{
      divisions: 0,
      elements: 0,
      characters: 0,
      editors: 0,
      sources: 0,
      paratexts: 0,
      places: 0,
      witnesses: 0,
      performances: 0
    }

  defp replaced_counts(%Play{id: id}) do
    %{
      divisions: count_rows(Division, id),
      elements: count_rows(Element, id),
      characters: count_rows(Character, id),
      editors: count_rows(PlayEditor, id, "tei"),
      sources: count_rows(PlaySource, id, "tei"),
      paratexts: count_rows(Paratext, id, "tei"),
      places: count_rows(Places.PlayPlace, id, "tei"),
      witnesses: count_rows(Witness, id, "tei"),
      performances: count_rows(Performance, id, "tei")
    }
  end

  defp preserved_counts(nil),
    do: %{editors: 0, sources: 0, paratexts: 0, places: 0, witnesses: 0, performances: 0}

  defp preserved_counts(%Play{id: id}) do
    %{
      editors: count_rows(PlayEditor, id) - count_rows(PlayEditor, id, "tei"),
      sources: count_rows(PlaySource, id) - count_rows(PlaySource, id, "tei"),
      paratexts: count_rows(Paratext, id) - count_rows(Paratext, id, "tei"),
      places: count_rows(Places.PlayPlace, id) - count_rows(Places.PlayPlace, id, "tei"),
      witnesses: count_rows(Witness, id) - count_rows(Witness, id, "tei"),
      performances: count_rows(Performance, id) - count_rows(Performance, id, "tei")
    }
  end

  defp preserved_fields(nil), do: []

  # The platform-owned columns a curator has set: those that differ from a new play's.
  defp preserved_fields(%Play{} = play) do
    Enum.filter(@platform_owned, &(Map.get(play, &1) != Map.get(%Play{}, &1)))
  end

  # The file's rows edited since their import, which a re-import replaces, an editor's
  # fixes with them: every row of the text, and the others that came from the file. An
  # import only inserts, so a fresh one counts none. A row typed by hand is kept, and an
  # edit within the second of its import does not show (timestamps are to the second).
  defp edited_count(nil), do: 0

  defp edited_count(%Play{id: id}) do
    edited = &from(r in &1, where: r.play_id == ^id and r.updated_at > r.inserted_at)
    from_file = &where(edited.(&1), origin: "tei")

    (Enum.map([Division, Element, Note, Character], edited) ++
       Enum.map(
         [PlayEditor, PlaySource, Paratext, Witness, Places.PlayPlace, Performance],
         from_file
       ))
    |> Enum.map(&Repo.aggregate(&1, :count))
    |> Enum.sum()
  end

  defp count_rows(schema, play_id) do
    Repo.aggregate(from(r in schema, where: r.play_id == ^play_id), :count, :id)
  end

  defp count_rows(schema, play_id, origin) do
    Repo.aggregate(
      from(r in schema, where: r.play_id == ^play_id and r.origin == ^origin),
      :count,
      :id
    )
  end

  # --- Writing ---

  # Everything the file supplies, in one transaction: the play, its header records, the
  # cast and front matter, then the text.
  defp write(tei) do
    play = write_play(tei.play)

    Enum.each(tei.editors, &Catalogue.create_play_editor(tei_row(&1, play)))
    Enum.each(tei.sources, &Catalogue.create_play_source(tei_row(&1, play)))
    write_witnesses(tei.witnesses, play)
    Enum.each(tei.places, &write_place(&1, nil))
    write_settings(tei.settings, play)

    Enum.each(
      tei.characters,
      &PlayContent.create_character_unless_exists(Map.put(&1, :play_id, play.id))
    )

    Enum.each(tei.paratexts, &Catalogue.create_paratext(tei_row(&1, play)))
    write_performances(tei.performances, play)

    cast = Map.new(PlayContent.list_characters(play.id), &{&1.xml_id, &1.id})
    write_text(tei.divisions, play, cast)
    write_bibliography(tei.bibliography, play)

    # Recompute verse_count from actual verse_line elements (the TEI header
    # <extent> value is often inaccurate or includes non-verse lines), and return
    # the play as that left it rather than the stale struct from before.
    {:ok, play} = Catalogue.update_verse_count(play.id)
    play
  end

  # Every editor, source, note, witness and performance the importer creates is stamped
  # `origin: "tei"`, so a re-import can replace its own rows and leave hand-entered ones
  # alone. Rows created anywhere else default to "manual".
  defp tei_row(attrs, play), do: Map.merge(attrs, %{play_id: play.id, origin: "tei"})

  # The original the file names waits on a first import only, like the link itself
  # (`parent_play_id` is platform-owned).
  defp write_play(attrs) do
    {original_code, attrs} = Map.pop(attrs, :pending_original_code)

    case Repo.get_by(Play, code: attrs.code) do
      %Play{} = existing_play ->
        reset_tei_content(existing_play)

        case Catalogue.update_play(existing_play, Map.drop(attrs, @platform_owned)) do
          {:ok, play} ->
            # An import of an archived play brings it back — the file is the reason it
            # is wanted again.
            play |> Ecto.Changeset.change(deleted_at: nil) |> Repo.update!()

          {:error, changeset} ->
            Repo.rollback(changeset)
        end

      nil ->
        case Catalogue.create_play(attrs, %Play{pending_original_code: original_code}) do
          {:ok, play} -> play
          {:error, changeset} -> Repo.rollback(changeset)
        end
    end
  end

  # A re-import replaces the text wholesale, but only the editors, sources and paratexts the
  # importer created itself. Anything a researcher typed — and every table later slices
  # add — stays. Deleting elements first lets the element_characters FK cascade handle
  # the join rows.
  defp reset_tei_content(%Play{id: id}) do
    for schema <- [Element, Division, Character] do
      Repo.delete_all(from(r in schema, where: r.play_id == ^id))
    end

    for schema <- [PlayEditor, PlaySource, Paratext, Witness] do
      Repo.delete_all(from(r in schema, where: r.play_id == ^id and r.origin == "tei"))
    end

    # Only the links, never the places: the gazetteer is corpus-global authority data,
    # and an orphaned place shows in the admin list with a play count of 0.
    Places.delete_tei_play_places(id)
  end

  # --- Witnesses ---

  # A siglum the play already has — a witness typed by hand, a modern edition in its
  # bibliography, or one earlier in the same file — is left out (Witnesses.taken_sigla/1,
  # after reset_tei_content/1 removed the file's own). So is a witness printing the same
  # line as one the play kept: most FileMaker witnesses have no siglum, and the play's own
  # export lists them. A witness with nothing to print fails its changeset and is left
  # out too.
  defp write_witnesses([], _play), do: :ok

  defp write_witnesses(witnesses, play) do
    kept = play.id |> Witnesses.list_for_play() |> MapSet.new(&Witnesses.plain/1)

    Enum.reduce(witnesses, Witnesses.taken_sigla(play.id), fn witness, taken ->
      attrs = tei_row(witness, play)

      if attrs.siglum in taken or Witnesses.plain(struct(Witness, attrs)) in kept do
        taken
      else
        _ = Witnesses.create_witness(attrs)
        if attrs.siglum, do: MapSet.put(taken, attrs.siglum), else: taken
      end
    end)

    :ok
  end

  # --- Performances ---

  # The file's performances replace the play's `tei` ones, which go through
  # `Performances.delete_performance/1` so that the companies, actors and source entries they
  # leave unused go with them; a curator's and FileMaker's stay. A performance of the file
  # that prints as one the play keeps is left out, as is a witness printing the same line.
  # The cast-list switch is one per play: the first performance to claim it has it, a later
  # claim in the file comes in without. A performance that fails its changeset is left out
  # too, as a witness is.
  defp write_performances(performances, play) do
    {own, kept} =
      play.id |> Performances.list_for_play() |> Enum.split_with(&(&1.origin == "tei"))

    Enum.each(own, &Performances.delete_performance/1)
    kept_prints = MapSet.new(kept, &(&1 |> as_parsed() |> printed()))

    Enum.reduce(performances, Enum.any?(kept, & &1.cast_from_cast_list), fn parsed,
                                                                            switch_taken? ->
      place_id = place_id(parsed.place)
      state_id = place_id(parsed.state)
      print = printed(%{parsed | place: place_id, state: state_id})

      unless MapSet.member?(kept_prints, print) do
        switch = parsed.cast_from_cast_list and not switch_taken?
        write_performance(parsed, play, place_id, state_id, switch)
      end

      switch_taken? or parsed.cast_from_cast_list
    end)

    :ok
  end

  defp write_performance(parsed, play, place_id, state_id, switch) do
    attrs =
      %{
        "play_id" => play.id,
        "origin" => "tei",
        "date_text" => parsed.date_text,
        "year_from" => parsed.year_from,
        "year_to" => parsed.year_to,
        "venue" => parsed.venue,
        "venue_type" => parsed.venue_type,
        "company_name" => parsed.company,
        "place_id" => place_id,
        "historical_state_id" => state_id,
        "note" => parsed.note,
        "cast_from_cast_list" => switch,
        "cast" => cast_rows(parsed.cast)
      }
      |> Map.merge(source_attrs(parsed, play))

    with {:error, reason} <- Performances.create_performance(attrs),
         do: Logger.warning("TEI import: left out a performance: #{inspect(reason)}")
  end

  # The place or state a performance names, by slug as a setting does; one the file does not
  # declare is dropped, the performance kept.
  defp place_id(nil), do: nil

  defp place_id(slug) do
    case Repo.get_by(Places.Place, slug: slug) do
      %{id: id} ->
        id

      nil ->
        Logger.warning("TEI import: a performance references unknown place #{inspect(slug)}")
        nil
    end
  end

  # A cast row is an actor found or created by name, which needs a surname or a nickname.
  defp cast_rows(cast) do
    {named, nameless} = Enum.split_with(cast, &(&1.surname || &1.nickname))

    if nameless != [],
      do: Logger.warning("TEI import: #{length(nameless)} cast row(s) name no actor, left out")

    for row <- named, do: Map.new(row, fn {field, value} -> {to_string(field), value} end)
  end

  # The source is the entry with the description the file gives, else a new one, as
  # `write_step/2` does for the bibliography. A source that is no valid entry is left out,
  # and with it the pages in it.
  defp source_attrs(%{source: nil}, _play), do: %{}

  defp source_attrs(%{source: description} = parsed, play) do
    volume_and_pages = %{
      "source_volume" => parsed.source_volume,
      "source_pages" => parsed.source_pages
    }

    cond do
      entry_id = Bibliography.identical_entries([description], play.id)[description] ->
        Map.put(volume_and_pages, "source_entry_id", entry_id)

      valid_entry?(description) ->
        Map.put(volume_and_pages, "source_entry", description)

      true ->
        Logger.warning("TEI import: a performance's source is no valid entry, left out")
        %{}
    end
  end

  # A stored performance in the shape the parser gives a file's (place and state as ids), to
  # be told from one by `printed/1`.
  defp as_parsed(performance) do
    %{
      date_text: performance.date_text,
      venue: performance.venue,
      venue_type: performance.venue_type,
      place: performance.place_id,
      state: performance.historical_state_id,
      company: performance.company && performance.company.name,
      note: performance.note,
      cast:
        for member <- performance.cast do
          %{
            role: member.role,
            surname: member.actor.surname,
            forename: member.actor.forename,
            nickname: member.actor.nickname
          }
        end,
      source: performance.source && Entry.description(performance.source),
      source_volume: performance.source_volume,
      source_pages: performance.source_pages,
      cast_from_cast_list: performance.cast_from_cast_list
    }
  end

  # What a page prints of a performance, as the changesets store it: the text squeezed, the
  # company without regard to case; its years and the actors' sex are not printed. Two
  # performances with the same `printed/1` are the same performance to a reader.
  defp printed(fields) do
    %{
      date_text: Text.squeeze(fields.date_text),
      venue: Text.squeeze(fields.venue),
      venue_type: fields.venue_type,
      place: fields.place,
      state: fields.state,
      company: fields.company |> Text.squeeze() |> then(&(&1 && String.downcase(&1))),
      note: Text.squeeze(fields.note),
      cast:
        for row <- fields.cast do
          Map.new(~w(role surname forename nickname)a, &{&1, Text.squeeze(row[&1])})
        end,
      source: fields.source,
      source_volume: Text.squeeze(fields.source_volume),
      source_pages: Text.squeeze(fields.source_pages),
      cast_from_cast_list: fields.cast_from_cast_list
    }
  end

  # --- Bibliography ---

  # What an import does with a file's references, decided once for the import and its
  # preview: `{:link, entry_id, ref}` for an entry Playcode has with the reference's
  # description (Bibliography.identical_entries/2) that the play does not link yet,
  # `{:create, nil, ref}` for one it has not, and `{:skip, nil, ref}` for one that is no
  # valid entry (a language or a list Playcode does not know). A reference the play links
  # already, or that the file gives twice, has no step. Nothing is ever changed or removed.
  defp bibliography_plan([], _play_id), do: []

  defp bibliography_plan(references, play_id) do
    found = Bibliography.identical_entries(Enum.map(references, & &1.description), play_id)
    linked = MapSet.new(Bibliography.linked_entry_ids(play_id))

    {steps, _seen} =
      Enum.flat_map_reduce(references, MapSet.new(), fn reference, seen ->
        if reference.description in seen do
          {[], seen}
        else
          {step(reference, found[reference.description], linked),
           MapSet.put(seen, reference.description)}
        end
      end)

    steps
  end

  defp step(reference, nil, _linked) do
    if valid_entry?(reference.description),
      do: [{:create, nil, reference}],
      else: [{:skip, nil, reference}]
  end

  defp step(reference, entry_id, linked) do
    if entry_id in linked, do: [], else: [{:link, entry_id, reference}]
  end

  # On every import, the first and every re-import. A write the database refuses (an
  # entry removed while the import ran) rolls the play back with a reason, not a crash.
  defp write_bibliography(references, play) do
    for step <- bibliography_plan(references, play.id), do: write_step(step, play)
    :ok
  end

  defp write_step({:skip, nil, reference}, _play),
    do: Logger.warning("Skipped a reference that is no valid entry: #{inspect(reference)}")

  defp write_step({step, entry_id, reference}, play) do
    place = %{volume: reference.volume, pages: reference.pages}

    result =
      if step == :link,
        do: Bibliography.link_entry(play.id, entry_id, place, "tei"),
        else: Bibliography.create_entry_for_play(play.id, reference.description, place, "tei")

    with {:error, reason} <- result, do: Repo.rollback({:bibliography, reason})
  end

  defp valid_entry?(description), do: Bibliography.change_entry(%Entry{}, description).valid?

  # --- Places ---

  # A place is found by its slug or created, then the places nested in it. The gazetteer
  # is corpus-global authority data: a place already there is used, never changed.
  defp write_place(%{attrs: attrs, slug_declared: slug_declared, places: places}, parent_id) do
    slug = attrs["slug"]

    case Places.find_or_create_by_slug(Map.put(attrs, "parent_place_id", parent_id)) do
      {:ok, place, outcome} ->
        cond do
          outcome != :existing ->
            :ok

          # No xml:id means the slug was derived from the name, so two distinct
          # referents that happen to share a name silently become one row. Our own
          # exporter always writes xml:id; a hand-authored file may not.
          not slug_declared ->
            Logger.warning(
              "TEI import: <place> without xml:id resolved to existing place #{inspect(slug)} " <>
                "by name — if these are different places, give each an xml:id"
            )

          true ->
            Logger.info("TEI import: place #{slug} already exists, left unchanged")
        end

        # Nested <place> elements are this place's children.
        Enum.each(places, &write_place(&1, place.id))

      {:error, changeset} ->
        Logger.warning("TEI import: could not create place #{slug}: #{inspect(changeset.errors)}")
    end
  end

  defp write_settings(settings, play) do
    Enum.each(settings, fn setting ->
      case Repo.get_by(Places.Place, slug: setting.slug) do
        nil ->
          Logger.warning("TEI import: setting references unknown place #{inspect(setting.slug)}")

        place ->
          # The state is always passed, nil included: a link the file wrote is refreshed
          # to what the file says, a file without a state clearing the old one.
          link_attrs = %{
            "role" => setting.role,
            "position" => setting.position,
            "note" => setting.note,
            "historical_state_id" => historical_state_id(setting.state, place),
            "origin" => "tei"
          }

          # A hand-linked place (origin "manual") surviving from before this file ever
          # mentioned it collides with the (play_id, place_id) unique index on a blind
          # insert — reset_tei_content only clears this play's own "tei" links, on
          # purpose. Leave the curated row alone: writing "tei" over its origin would
          # hand it to reset_tei_content, and the next re-import would delete it along
          # with its note. Only a link this importer already owns gets refreshed.
          case Repo.get_by(Places.PlayPlace, play_id: play.id, place_id: place.id) do
            nil ->
              Places.link_place(play.id, place.id, link_attrs)

            %{origin: "tei"} = existing ->
              Places.update_play_place(existing, link_attrs)

            existing ->
              Logger.info(
                "TEI import: <setting> names #{inspect(setting.slug)}, already linked with " <>
                  "origin #{inspect(existing.origin)} — left untouched"
              )
          end
      end
    end)
  end

  # The state a link names, by slug as its place is. One the file does not declare, or the
  # place itself (the changeset refuses it, and the link would be lost), is no state.
  defp historical_state_id(nil, _place), do: nil

  defp historical_state_id(slug, place) do
    case Repo.get_by(Places.Place, slug: slug) do
      %{id: id} when id != place.id ->
        id

      _ ->
        Logger.warning(
          "TEI import: #{inspect(place.slug)} names #{inspect(slug)} as its historical state, " <>
            "which is unknown or the place itself"
        )

        nil
    end
  end

  # --- Text ---

  # The text in a handful of statements, not one per row: an import is one transaction,
  # and production's database timeout covers all of it (7,565 round trips for AL0788).
  # Every row is checked by its changeset as `PlayContent` would create it, given its id
  # here so its children can point at it, then written with insert_all, parents first.
  # Anything `PlayContent.create_*` does beyond its changeset does not reach this path.
  defp write_text(divisions, play, cast) do
    rows =
      Enum.reduce(
        divisions,
        %{Division => [], Element => [], ElementCharacter => [], Note => []},
        &collect_division(&1, play, nil, cast, &2)
      )

    now = DateTime.utc_now(:second)

    for schema <- [Division, Element, ElementCharacter, Note] do
      rows |> Map.fetch!(schema) |> Enum.reverse() |> insert_rows(schema, now)
    end
  end

  # A division, the notes in its heading, its elements, then its subdivisions. Positions
  # come from the file; parents from where the row sits in the tree.
  defp collect_division(division, play, parent_id, cast, rows) do
    row =
      %Division{id: Ecto.UUID.generate()}
      |> Division.changeset(
        division
        |> Map.drop([:notes, :elements, :divisions])
        |> Map.merge(%{play_id: play.id, parent_id: parent_id})
      )
      |> checked(&{:division_create_failed, &1})

    rows = rows |> add(Division, row) |> collect_notes(division.notes, :division_id, row, play)
    rows = Enum.reduce(division.elements, rows, &collect_element(&1, play, row.id, nil, cast, &2))
    Enum.reduce(division.divisions, rows, &collect_division(&1, play, row.id, cast, &2))
  end

  defp collect_element(element, play, division_id, parent_id, cast, rows) do
    row =
      %Element{id: Ecto.UUID.generate()}
      |> Element.changeset(
        element
        |> Map.drop([:who, :notes, :elements])
        |> Map.merge(%{play_id: play.id, division_id: division_id, parent_id: parent_id})
      )
      # The type is one of the parser's six, never a value from the file.
      |> checked(&{:element_create_failed, String.to_atom(element.type), &1})

    speakers =
      for {character_id, position} <- Enum.with_index(character_ids(element, cast)) do
        %ElementCharacter{
          id: Ecto.UUID.generate(),
          element_id: row.id,
          character_id: character_id,
          position: position
        }
      end

    rows = Enum.reduce(speakers, add(rows, Element, row), &add(&2, ElementCharacter, &1))
    rows = collect_notes(rows, element.notes, :element_id, row, play)

    Enum.reduce(element.elements, rows, &collect_element(&1, play, division_id, row.id, cast, &2))
  end

  # Notes in document order, each after the notes before it at the same offset, as
  # `PlayContent.create_note/1` places them.
  defp collect_notes(rows, notes, anchor, anchor_row, play) do
    {rows, _next} =
      Enum.reduce(notes, {rows, %{}}, fn note, {rows, next} ->
        row =
          %Note{id: Ecto.UUID.generate()}
          |> Note.changeset(Map.merge(note, %{anchor => anchor_row.id, play_id: play.id}))
          |> checked(&{:note_create_failed, &1})

        position = Map.get(next, row.offset, 0)
        {add(rows, Note, %{row | position: position}), Map.put(next, row.offset, position + 1)}
      end)

    rows
  end

  defp add(rows, schema, row), do: Map.update!(rows, schema, &[row | &1])

  # The row a valid changeset makes; an invalid one rolls the import back with `error`.
  defp checked(changeset, error) do
    case Ecto.Changeset.apply_action(changeset, :insert) do
      {:ok, row} -> row
      {:error, changeset} -> Repo.rollback(error.(changeset))
    end
  end

  # Every stored field, timestamps set, in batches well under Postgres's 65,535
  # parameters a statement. Rows in the order given, so a parent precedes its children.
  defp insert_rows(rows, schema, now) do
    fields = schema.__schema__(:fields)

    rows
    |> Enum.map(&(&1 |> Map.take(fields) |> Map.merge(%{inserted_at: now, updated_at: now})))
    |> Enum.chunk_every(1_000)
    |> Enum.each(&Repo.insert_all(schema, &1))
  end

  # The characters a speech's `who` names. A ref to no one in the cast is dropped, and a
  # repeated one ("#horatio #barnardo #marcellus #barnardo") counted once, which the
  # element_characters unique index requires.
  defp character_ids(%{who: who}, cast),
    do: who |> Enum.map(&cast[&1]) |> Enum.reject(&is_nil/1) |> Enum.uniq()

  defp character_ids(_element, _cast), do: []
end
