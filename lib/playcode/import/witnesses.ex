defmodule Playcode.Import.Witnesses do
  @moduledoc """
  The one-time move of FileMaker's witnesses into Playcode (S3). Spec: "Import" in
  docs/superpowers/specs/2026-10-10-s3-witnesses-design.md.

  `load/1` reads `T03` and `T03.2`. `plan/2` decides what to write: it reads the database
  but never writes. `apply_plan/2` writes the plan in one transaction.

  A play the import has written to before (a `filemaker` witness, or its "import" row in
  the activity log, which outlives the witnesses) is skipped whole, so a re-run picks up
  the plays added since without undoing a curator's edits or deletions.
  """

  import Ecto.Query

  alias Playcode.ActivityLog
  alias Playcode.Import.{FilemakerSync, FilemakerXml}
  alias Playcode.Repo
  alias Playcode.Witnesses
  alias Playcode.Witnesses.Witness

  @default_dir "doc/ctce_dades"

  @files [witnesses: "T03_ObraTestimonio.xml", attributions: "T03.2_Atribucion.xml"]

  # T03.1 by id. "No consta" (4, 7) is its parent; the deepest level a record sets wins.
  @types %{
    "2" => "manuscript",
    "3" => "early_edition",
    "4" => "manuscript",
    "5" => "autograph",
    "6" => "copy",
    "7" => "early_edition",
    "8" => "collection",
    "9" => "loose",
    "10" => "collection_single_author",
    "11" => "collection_several_authors"
  }

  # T03 rows that are FileMaker's own tests: "TituloTestimonio", siglum "TES".
  @test_records ~w(32)

  @described ~w(ObrTes_TituloTestimonio ObrTes_TituloNormalizado ObrTes_Observacion)

  def default_dir, do: @default_dir

  @doc "Reads the two tables from `dir`."
  def load(dir) do
    Enum.reduce_while(@files, {:ok, %{}}, fn {key, file}, {:ok, data} ->
      case FilemakerXml.read(Path.join(dir, file)) do
        {:ok, rows} -> {:cont, {:ok, Map.put(data, key, rows)}}
        {:error, reason} -> {:halt, {:error, {file, reason}}}
      end
    end)
  end

  @doc "Attribution names by id, from `T03.2`."
  def attributions(data),
    do: Map.new(data.attributions, &{&1["_kp_IdAtribucion"], value(&1, "_tc_Atr_Atribucion")})

  @doc "Why a `T03` row is not imported whatever play it names: `:test_record`, `:empty`, or nil."
  def skip_reason(row) do
    cond do
      row["_kp_IdObraTestimonio"] in @test_records -> :test_record
      Enum.all?(@described, &is_nil(value(row, &1))) -> :empty
      true -> nil
    end
  end

  @doc "A `T03` row as witness attributes, its attribution looked up in `attributions`."
  def witness_attrs(row, attributions) do
    %{
      siglum: value(row, "ObrTes_Siglas"),
      title: value(row, "ObrTes_TituloTestimonio"),
      normalized_title: value(row, "ObrTes_TituloNormalizado"),
      attribution: attributions[value(row, "_k_IdAtribucion")],
      pub_place: value(row, "ObrTes_Ciudad"),
      publisher: value(row, "ObrTes_Editorial"),
      date: value(row, "ObrTes_Anyo"),
      format: value(row, "ObrTes_Formato"),
      witness_type:
        Enum.find_value(
          ~w(_k_IdTesTip_Nivel3 _k_IdTesTip_Nivel2 _k_IdTesTip_Nivel1),
          &@types[value(row, &1)]
        ),
      shelfmark: value(row, "ObrTes_SignaturaFI"),
      note: value(row, "ObrTes_Observacion")
    }
  end

  @doc "What `apply_plan/2` would write. Reads the database, writes nothing. See the moduledoc."
  def plan(data, plays) do
    attributions = attributions(data)

    context = %{
      by_code: Enum.group_by(plays, &FilemakerSync.base_code(&1.code)),
      imported: imported_play_ids(),
      sigla: existing_sigla()
    }

    empty = %{
      witnesses: [],
      already_imported: MapSet.new(),
      skipped: %{},
      dropped: [],
      not_held: 0
    }

    acc =
      data.witnesses
      |> Enum.sort_by(&String.to_integer(&1["_kp_IdObraTestimonio"]))
      |> Enum.reduce(empty, fn row, acc ->
        ref = "T03:" <> row["_kp_IdObraTestimonio"]

        case skip_reason(row) do
          nil ->
            place(acc, context, ref, witness_attrs(row, attributions), row["_k_IdObraTitulo"])

          reason ->
            skip(acc, reason, ref)
        end
      end)

    %{
      witnesses: Enum.reverse(acc.witnesses),
      already_imported: acc.already_imported |> MapSet.to_list() |> Enum.sort(),
      skipped: Map.new(acc.skipped, fn {reason, refs} -> {reason, Enum.reverse(refs)} end),
      dropped: Enum.reverse(acc.dropped),
      not_held: acc.not_held
    }
  end

  @doc """
  Writes the plan in one transaction: each play's witnesses in FileMaker's order, after any
  it already has, then one activity-log entry per play. Returns `{:ok, %{witnesses: n}}`.
  """
  def apply_plan(plan, opts \\ []) do
    Repo.transaction(
      fn ->
        Enum.each(plan.witnesses, fn w ->
          {:ok, _} =
            Witnesses.create_witness(
              Map.put(w, :origin, "filemaker"),
              %Witness{filemaker_id: w.filemaker_id}
            )
        end)

        plan.witnesses
        |> Enum.group_by(& &1.play_id)
        |> Enum.each(fn {play_id, witnesses} ->
          ActivityLog.log!(%{
            user_id: opts[:user_id],
            play_id: play_id,
            action: "import",
            resource_type: "play_witness",
            resource_id: play_id,
            changes: %{"witnesses" => length(witnesses)},
            metadata: %{"source" => "filemaker"}
          })
        end)

        %{witnesses: length(plan.witnesses)}
      end,
      timeout: :infinity
    )
  end

  @doc "The plan as lines of text, for the mix task and the release."
  def report(plan) do
    per_play =
      plan.witnesses
      |> Enum.group_by(& &1.code)
      |> Enum.sort()
      |> Enum.map(fn {code, witnesses} -> "#{code}  #{length(witnesses)} witnesses" end)

    plays = plan.witnesses |> Enum.uniq_by(& &1.play_id) |> length()

    skipped =
      for {reason, refs} <- Enum.sort(plan.skipped) do
        "skipped, #{reason}: #{length(refs)}  #{Enum.join(refs, ", ")}"
      end

    per_play ++
      [
        "",
        "witnesses: #{length(plan.witnesses)} on #{plays} plays",
        "attribution dropped: #{length(plan.dropped)}  #{Enum.join(plan.dropped, ", ")}"
      ] ++
      skipped ++
      [
        "already imported: #{length(plan.already_imported)} plays #{Enum.join(plan.already_imported, ", ")}",
        "witnesses on versions not held: #{plan.not_held}"
      ]
  end

  defp place(acc, context, ref, attrs, version) do
    case Map.get(context.by_code, version_code(version), []) do
      [] -> %{acc | not_held: acc.not_held + 1}
      plays -> Enum.reduce(plays, acc, &place_on(&2, context, ref, attrs, &1))
    end
  end

  defp place_on(acc, context, ref, attrs, play) do
    cond do
      MapSet.member?(context.imported, play.id) ->
        %{acc | already_imported: MapSet.put(acc.already_imported, play.code)}

      attrs.siglum && MapSet.member?(context.sigla, {play.id, attrs.siglum}) ->
        skip(acc, :siglum_taken, "#{ref} on #{play.code}")

      true ->
        {attrs, acc} = drop_misattribution(attrs, acc, "#{ref} on #{play.code}", play)
        witness = Map.merge(attrs, %{play_id: play.id, code: play.code, filemaker_id: ref})
        %{acc | witnesses: [witness | acc.witnesses]}
    end
  end

  # Jodelle is FileMaker's first attribution record, left on witnesses of Spanish plays by
  # the picker's default (the spec, "Attributions dropped"). On his own plays it is right.
  defp drop_misattribution(attrs, acc, label, play) do
    if is_binary(attrs.attribution) and attrs.attribution =~ "Jodelle" and
         not String.contains?(play.author_name || "", "Jodelle") do
      {%{attrs | attribution: nil}, %{acc | dropped: [label | acc.dropped]}}
    else
      {attrs, acc}
    end
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

  defp value(row, field) do
    case row[field] do
      nil -> nil
      text -> if String.trim(text) == "", do: nil, else: String.trim(text)
    end
  end

  # A play is done once the import has written to it. Its filemaker witnesses alone are no
  # marker: a curator may delete every one, and the next run must not bring them back. The
  # activity-log row apply_plan/2 writes per play survives that.
  defp imported_play_ids do
    logged =
      ActivityLog.Entry
      |> where([a], a.action == "import" and a.resource_type == "play_witness")
      |> select([a], a.play_id)

    Witness
    |> where([w], w.origin == "filemaker")
    |> select([w], w.play_id)
    |> union(^logged)
    |> Repo.all()
    |> MapSet.new()
  end

  # `{play_id, siglum}` for every witness the plays already have.
  defp existing_sigla do
    Witness
    |> where([w], not is_nil(w.siglum))
    |> select([w], {w.play_id, w.siglum})
    |> Repo.all()
    |> MapSet.new()
  end
end
