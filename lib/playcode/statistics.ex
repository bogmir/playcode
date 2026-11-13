defmodule Playcode.Statistics do
  @moduledoc """
  Computes and caches play statistics from the structured content.
  """

  import Ecto.Query
  alias Playcode.Repo
  alias Playcode.Catalogue.Play
  alias Playcode.Statistics.PlayStatistic
  alias Playcode.PlayContent
  alias Playcode.PlayContent.{Division, Element, InlineMarkup}
  alias Playcode.Statistics.Metrics

  # Bump when compute/1 changes what it stores: a cached row with another version is
  # recomputed on its next read, so no migration or manual recompute is needed.
  # 11: a row per division as well as per scene, with prose passages (2026-11-13); the
  # figures no page reads dropped.
  @version 11

  # A cached row is current only for the play's content_version it was computed at:
  # Postgres moves that version on every edit to the play's text, so no edit has to
  # remember to invalidate the cache, and a row a concurrent read stored from the old
  # text after an edit committed is never served.
  def get_statistics(play_id) do
    content_version = content_version(play_id)

    case Repo.get_by(PlayStatistic, play_id: play_id) do
      %PlayStatistic{data: %{"version" => @version, "content_version" => ^content_version}} =
          stat ->
        stat

      _missing_or_stale ->
        compute_and_store(play_id, content_version)
    end
  end

  def recompute(play_id) do
    compute_and_store(play_id, content_version(play_id))
  end

  defp content_version(play_id),
    do: Repo.one(from p in Play, where: p.id == ^play_id, select: p.content_version)

  # The version is read before the content, so an edit that commits mid-compute leaves
  # this row older than the play, and the next read computes again.
  defp compute_and_store(play_id, content_version) do
    data = play_id |> compute() |> Map.put("content_version", content_version)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # An upsert: the static site's parallel builds read one play's statistics at once.
    %PlayStatistic{}
    |> PlayStatistic.changeset(%{play_id: play_id, data: data, computed_at: now})
    |> Repo.insert!(
      on_conflict: {:replace, [:data, :computed_at, :updated_at]},
      conflict_target: :play_id,
      returning: true
    )
  end

  defp compute(play_id) do
    acts = list_acts(play_id)
    all_elements = list_all_elements(play_id)

    items = play_id |> PlayContent.load_play_content() |> Metrics.items()
    passages = Metrics.passages(items)
    {basis, columns, column_of} = Metrics.columns(items, passages)
    spoken = Enum.filter(items, &(&1.kind in [:verse, :prose]))

    %{
      "version" => @version,
      "act_label" => act_label(acts),
      "num_acts" => length(acts),
      "scenes" => count_scenes(play_id),
      "split_verses" => count_split_verses(all_elements),
      "total_prose_fragments" => count_by_type(all_elements, "prose"),
      "total_stage_directions" =>
        count_by_type(all_elements, "stage_direction") + inline_stages(all_elements),
      "total_asides" => count_asides(all_elements),
      "aside_verses" => count_aside_verses(all_elements),
      "metrical_passages" => Enum.map(passages, &passage_data/1),
      "verses" => Enum.count(items, &Metrics.whole_verse?/1),
      "speeches" => count_by_type(all_elements, "speech"),
      "words" => spoken |> Enum.map(&Metrics.words(&1.element.content)) |> Enum.sum(),
      "characters" => Metrics.characters(items, passages, column_of),
      "presence" => %{"basis" => basis, "columns" => columns},
      "divisions" => Metrics.divisions(items)
    }
  end

  defp passage_data(passage) do
    %{
      "act" => passage.act,
      "form" => passage.form,
      "from" => passage.from,
      "to" => passage.to,
      "verses" => passage.verses
    }
  end

  @act_types ~w(acto act acte jornada)
  @scene_types ~w(escena scene scène)

  defp list_acts(play_id) do
    Division
    |> where(play_id: ^play_id)
    |> where([d], d.type in @act_types)
    |> where([d], is_nil(d.parent_id))
    |> order_by(:position)
    |> Repo.all()
  end

  defp act_label([%{type: type} | _]), do: type
  defp act_label([]), do: "act"

  defp list_all_elements(play_id), do: Repo.all(where(Element, play_id: ^play_id))

  defp count_scenes(play_id),
    do:
      Repo.aggregate(
        where(Division, [d], d.play_id == ^play_id and d.type in @scene_types),
        :count
      )

  defp count_by_type(elements, type) do
    Enum.count(elements, &(&1.type == type))
  end

  defp inline_stages(elements),
    do: elements |> Enum.map(&InlineMarkup.stage_count(&1.content)) |> Enum.sum()

  defp count_split_verses(elements) do
    Enum.count(elements, &(&1.type == "verse_line" && &1.part == "I"))
  end

  defp count_asides(elements) do
    elements |> Enum.map(&Element.asides_started/1) |> Enum.sum()
  end

  defp count_aside_verses(elements) do
    elements
    |> Enum.filter(&(&1.type == "verse_line" && &1.is_aside))
    |> Enum.count()
  end
end
