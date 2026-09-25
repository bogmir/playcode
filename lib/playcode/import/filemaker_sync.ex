defmodule Playcode.Import.FilemakerSync do
  @moduledoc """
  Applies the FileMaker export to the plays we already have.

  `plan/3` is pure: it produces the list of changes without writing anything, so the
  mix task can print it for review. `apply_plan/2` performs the writes.

  Two write policies, deliberately:

    * **Derived fields** — `language`, `relationship_type`, `parent_play_id`. The
      published index is authoritative, so a difference is an error in our data and
      gets overwritten.
    * **Curated fields** — `historical_time`, `historical_time_note` and the three
      `composition_date_*` columns. A researcher is expected to edit these in the admin
      form, so the export is a bootstrap: a blank column is filled, a disagreement is
      reported under `:conflicts` and left alone, and only `force: true` overwrites it.

  Nothing here ever creates a play. Codes with no index entry — every Artelope play,
  and anything the project never published — come back under `:missing`.

  A dating the export carries but the parse refused comes back under `:skipped`, which
  is read-only: `apply_plan/2` ignores it, and unlike a conflict there is nothing to
  tick, because the whole point is that the value is not fit to write.
  """

  import Ecto.Query

  alias Playcode.ActivityLog
  alias Playcode.Catalogue
  alias Playcode.Catalogue.Play
  alias Playcode.Repo

  @keep :keep
  @languages ~w(es en fr it pt)
  @curated [
    :historical_time,
    :historical_time_note,
    :composition_date_from,
    :composition_date_to,
    :composition_date_note
  ]

  # The columns of a dating the index carries but the version record does not.
  @index_curated [:composition_date_from, :composition_date_to, :composition_date_note]

  @doc "The FileMaker code hiding at the front of a play code."
  def base_code(code), do: code |> String.split("_") |> List.first()

  @doc "Every play not archived, for `plan/2`. An archived play is not synced."
  def all_plays do
    Play |> where([p], is_nil(p.deleted_at)) |> order_by([p], p.code) |> Repo.all()
  end

  @doc "Diffs the export against the given plays. Writes nothing."
  def plan(index, plays, versions \\ %{}) do
    by_code = Map.new(plays, &{base_code(&1.code), &1})
    empty = %{changes: [], unchanged: [], missing: [], conflicts: [], skipped: []}

    plays
    |> Enum.reduce(empty, fn play, acc ->
      code = base_code(play.code)
      indexed = Map.get(index, code, %{})

      # The two sources are independent. A play absent from the published index is
      # still reported as missing, but it can have a T01 research record — EMOTHE0341
      # does — and that fill must not be skipped.
      {derived, acc} =
        case Map.fetch(index, code) do
          :error -> {%{}, %{acc | missing: [code | acc.missing]}}
          {:ok, version} -> {changes_for(play, version, by_code), acc}
        end

      # The composition dating splits across both sources: the index header carries the
      # accepted years, T01 the competing datings. T01's note wins, but only when it has
      # one — a plain merge would let its nils erase the header fallback.
      curated =
        indexed
        |> Map.take(@index_curated)
        |> Map.merge(reject_blank(Map.get(versions, code, %{})))

      sets = Map.merge(derived, fills_for(play, curated))

      acc = %{
        acc
        | conflicts: conflicts_for(play, curated, code) ++ acc.conflicts,
          skipped: skipped_for(indexed, play, code) ++ acc.skipped
      }

      cond do
        map_size(sets) > 0 ->
          change = %{play_id: play.id, code: code, title: play.title, sets: sets}
          %{acc | changes: [change | acc.changes]}

        Map.has_key?(index, code) ->
          %{acc | unchanged: [code | acc.unchanged]}

        true ->
          acc
      end
    end)
    |> Map.new(fn {key, list} -> {key, Enum.reverse(list)} end)
  end

  @doc """
  Writes every change in the plan and logs it. Returns one result per play written.

  `force: true` also writes the conflicts — the curated values a researcher edited that
  disagree with the export. Without it they are left alone.
  """
  def apply_plan(plan, opts \\ []) do
    user_id = Keyword.get(opts, :user_id)
    force = Keyword.get(opts, :force, false)

    plan
    |> writes(force)
    |> Enum.map(fn change ->
      play = Catalogue.get_play!(change.play_id)

      case Catalogue.update_play(play, change.sets) do
        {:ok, updated} ->
          ActivityLog.log!(%{
            user_id: user_id,
            play_id: updated.id,
            action: "update",
            resource_type: "play",
            resource_id: updated.id,
            changes: stringify(change.sets),
            metadata: %{"source" => "filemaker_index"}
          })

          {:ok, change.code}

        {:error, changeset} ->
          {:error, change.code, changeset}
      end
    end)
  end

  defp writes(plan, false), do: plan.changes

  defp writes(plan, true) do
    forced =
      Enum.reduce(plan.conflicts, %{}, fn conflict, acc ->
        Map.update(
          acc,
          conflict.play_id,
          %{
            play_id: conflict.play_id,
            code: conflict.code,
            title: conflict.title,
            sets: %{conflict.field => conflict.indexed}
          },
          fn change -> put_in(change.sets[conflict.field], conflict.indexed) end
        )
      end)

    # A play can be in both buckets — one field filled, another conflicting.
    plan.changes
    |> Enum.map(fn change ->
      case Map.pop(forced, change.play_id) do
        {nil, _rest} -> change
        {extra, _rest} -> %{change | sets: Map.merge(change.sets, extra.sets)}
      end
    end)
    |> Kernel.++(
      Enum.reject(Map.values(forced), fn forced_change ->
        Enum.any?(plan.changes, &(&1.play_id == forced_change.play_id))
      end)
    )
  end

  defp stringify(sets) do
    Map.new(sets, fn {key, value} -> {Atom.to_string(key), value} end)
  end

  defp changes_for(play, version, by_code) do
    %{
      language: language_for(version),
      relationship_type: relationship_for(version),
      parent_play_id: parent_for(version, by_code)
    }
    |> Enum.reject(fn {_key, value} -> value == @keep end)
    |> Enum.reject(fn {key, value} -> Map.get(play, key) == value end)
    |> Map.new()
  end

  # Curated fields are filled only when the column is blank. See the moduledoc.
  defp fills_for(play, curated) do
    @curated
    |> Enum.filter(fn key -> blank?(Map.get(play, key)) and not blank?(Map.get(curated, key)) end)
    |> Map.new(fn key -> {key, Map.get(curated, key)} end)
  end

  defp conflicts_for(play, curated, code) do
    for key <- @curated,
        current = Map.get(play, key),
        indexed = Map.get(curated, key),
        not blank?(current),
        not blank?(indexed),
        current != indexed do
      %{
        play_id: play.id,
        code: code,
        title: play.title,
        field: key,
        current: current,
        indexed: indexed
      }
    end
  end

  # T01 supplies a note for a handful of plays and nil for the rest. Those nils must not
  # win the merge against the index header.
  defp reject_blank(curated) do
    Map.reject(curated, fn {_key, value} -> blank?(value) end)
  end

  # A dating the parse refused — too wide a span, or a header with no year. Its own
  # bucket rather than :conflicts, because a conflict is tickable in /admin/filemaker and
  # force-writing a bad span is exactly what the guard exists to prevent.
  defp skipped_for(%{composition_date_skipped: {reason, value}}, play, code) do
    [%{play_id: play.id, code: code, title: play.title, reason: reason, value: value}]
  end

  defp skipped_for(_indexed, _play, _code), do: []

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false

  defp language_for(%{lang: lang}) when lang in @languages, do: lang
  defp language_for(_version), do: @keep

  defp relationship_for(%{role: :editor}), do: nil
  defp relationship_for(%{role: :translator}), do: "traduccion"
  defp relationship_for(_version), do: @keep

  defp parent_for(version, by_code) do
    head = Enum.find(version.family, &(&1.role == :editor))

    cond do
      is_nil(head) ->
        @keep

      head.code == version.code ->
        nil

      true ->
        case Map.fetch(by_code, head.code) do
          {:ok, parent} -> parent.id
          :error -> @keep
        end
    end
  end
end
