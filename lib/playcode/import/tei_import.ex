defmodule Playcode.Import.TeiImport do
  @moduledoc """
  Imports a TEI-XML file: `Playcode.Import.TeiParser` reads it, this module writes what
  it read, in one transaction.

  A re-import updates the play with that code in place. It replaces the play's whole
  text and the editors, sources, paratexts, witnesses and place links the importer
  created itself (`origin: "tei"`); everything a researcher typed is kept, and so are the
  columns the platform owns. `preview_import/1` reports that before anything is written.
  """

  import Ecto.Query

  alias Playcode.Bibliography
  alias Playcode.Bibliography.{Citation, Entry, Link}
  alias Playcode.Catalogue
  alias Playcode.Catalogue.{Play, PlayEditor, PlaySource, Paratext}
  alias Playcode.Import.TeiParser
  alias Playcode.PlayContent
  alias Playcode.PlayContent.{Character, Division, Element, Note}
  alias Playcode.Places
  alias Playcode.Repo
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

  Those five tables — editors, sources, paratexts, places and witnesses — hold both TEI-imported and
  hand-entered rows, so `:replaces` and `:preserves` split each one by `origin`. Both
  the admin import page and the `--dry-run` output report the totals, and adding a
  fifth such table must not mean remembering two more addition sites.
  """
  def mixed_ownership_total(counts) do
    [:editors, :sources, :paratexts, :places, :witnesses]
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
      witnesses: 0
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
      witnesses: count_rows(Witness, id, "tei")
    }
  end

  defp preserved_counts(nil), do: %{editors: 0, sources: 0, paratexts: 0, places: 0, witnesses: 0}

  defp preserved_counts(%Play{id: id}) do
    %{
      editors: count_rows(PlayEditor, id) - count_rows(PlayEditor, id, "tei"),
      sources: count_rows(PlaySource, id) - count_rows(PlaySource, id, "tei"),
      paratexts: count_rows(Paratext, id) - count_rows(Paratext, id, "tei"),
      places: count_rows(Places.PlayPlace, id) - count_rows(Places.PlayPlace, id, "tei"),
      witnesses: count_rows(Witness, id) - count_rows(Witness, id, "tei")
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
       Enum.map([PlayEditor, PlaySource, Paratext, Witness, Places.PlayPlace], from_file))
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

    cast = Map.new(PlayContent.list_characters(play.id), &{&1.xml_id, &1.id})
    Enum.each(tei.divisions, &write_division(&1, play, nil, cast))
    write_bibliography(tei.bibliography, play)

    # Recompute verse_count from actual verse_line elements (the TEI header
    # <extent> value is often inaccurate or includes non-verse lines), and return
    # the play as that left it rather than the stale struct from before.
    {:ok, play} = Catalogue.update_verse_count(play.id)
    play
  end

  # Every editor, source, note and witness the importer creates is stamped
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
    if valid_reference?(reference),
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

  defp valid_reference?(reference),
    do: Bibliography.change_entry(%Entry{}, reference.description).valid?

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
          link_attrs = %{
            "role" => setting.role,
            "position" => setting.position,
            "note" => setting.note,
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

  # --- Text ---

  # A division, the notes in its heading, its elements, then its subdivisions. Positions
  # come from the file; parents from where the row sits in the tree.
  defp write_division(division, play, parent_id, cast) do
    attrs =
      division
      |> Map.drop([:notes, :elements, :divisions])
      |> Map.merge(%{play_id: play.id, parent_id: parent_id})

    row =
      case PlayContent.create_division(attrs) do
        {:ok, row} -> row
        {:error, cs} -> Repo.rollback({:division_create_failed, cs})
      end

    write_notes(division.notes, %{division_id: row.id}, play)
    Enum.each(division.elements, &write_element(&1, play, row.id, nil, cast))
    Enum.each(division.divisions, &write_division(&1, play, row.id, cast))
  end

  defp write_element(element, play, division_id, parent_id, cast) do
    attrs =
      element
      |> Map.drop([:who, :notes, :elements])
      |> Map.merge(%{play_id: play.id, division_id: division_id, parent_id: parent_id})

    row =
      case PlayContent.create_element(attrs) do
        {:ok, row} ->
          row

        # The type is one of the parser's six, never a value from the file.
        {:error, cs} ->
          Repo.rollback({:element_create_failed, String.to_atom(element.type), cs})
      end

    write_notes(element.notes, %{element_id: row.id}, play)

    case character_ids(element, cast) do
      [] -> :ok
      ids -> PlayContent.set_element_characters(row.id, ids)
    end

    Enum.each(element.elements, &write_element(&1, play, division_id, row.id, cast))
  end

  # The characters a speech's `who` names. A ref to no one in the cast is dropped, and a
  # repeated one ("#horatio #barnardo #marcellus #barnardo") counted once, which the
  # element_characters unique index requires.
  defp character_ids(%{who: who}, cast),
    do: who |> Enum.map(&cast[&1]) |> Enum.reject(&is_nil/1) |> Enum.uniq()

  defp character_ids(_element, _cast), do: []

  # Notes in document order: `create_note/1` puts each after the notes already at its
  # offset.
  defp write_notes(notes, anchor, play) do
    Enum.each(notes, fn note ->
      case PlayContent.create_note(note |> Map.merge(anchor) |> Map.put(:play_id, play.id)) do
        {:ok, _note} -> :ok
        {:error, cs} -> Repo.rollback({:note_create_failed, cs})
      end
    end)
  end
end
