defmodule Playcode.Statistics do
  @moduledoc """
  Computes and caches play statistics from the structured content.
  """

  import Ecto.Query
  alias Playcode.Repo
  alias Playcode.Statistics.PlayStatistic
  alias Playcode.PlayContent.{Division, Element, ElementCharacter}

  # Bump when compute/1 changes what it stores: a cached row with another version is
  # recomputed on its next read, so no migration or manual recompute is needed.
  @version 2

  def get_statistics(play_id) do
    case Repo.get_by(PlayStatistic, play_id: play_id) do
      %PlayStatistic{data: %{"version" => @version}} = stat -> stat
      _missing_or_stale -> compute_and_store(play_id)
    end
  end

  def recompute(play_id) do
    compute_and_store(play_id)
  end

  def delete_statistics(play_id) do
    case Repo.get_by(PlayStatistic, play_id: play_id) do
      nil -> :ok
      stat -> Repo.delete(stat)
    end
  end

  defp compute_and_store(play_id) do
    data = compute(play_id)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs = %{play_id: play_id, data: data, computed_at: now}

    case Repo.get_by(PlayStatistic, play_id: play_id) do
      nil ->
        %PlayStatistic{}
        |> PlayStatistic.changeset(attrs)
        |> Repo.insert!()

      existing ->
        existing
        |> PlayStatistic.changeset(attrs)
        |> Repo.update!()
    end
  end

  defp compute(play_id) do
    acts = list_acts(play_id)
    all_elements = list_all_elements(play_id)

    # Map division_id -> act number for elements
    division_to_act = build_division_to_act_map(play_id, acts)

    %{
      "version" => @version,
      "act_label" => act_label(acts),
      "num_acts" => length(acts),
      "scenes" => compute_scenes(play_id, acts),
      "total_verses" => count_by_type(all_elements, "verse_line"),
      "verse_distribution" => verse_distribution(all_elements, division_to_act, acts),
      "split_verses" => count_split_verses(all_elements),
      "prose_fragments" => count_prose_fragments(all_elements, division_to_act, acts),
      "total_prose_fragments" => count_by_type(all_elements, "prose"),
      "total_stage_directions" => count_by_type(all_elements, "stage_direction"),
      "total_asides" => count_asides(all_elements),
      "aside_verses" => count_aside_verses(all_elements),
      "character_appearances" => character_appearances(all_elements),
      "verse_type_distribution" => verse_type_distribution(all_elements)
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

  defp list_all_elements(play_id) do
    ec_preload = from(ec in ElementCharacter, order_by: ec.position, preload: :character)

    Element
    |> where(play_id: ^play_id)
    |> preload(element_characters: ^ec_preload)
    |> Repo.all()
  end

  defp build_division_to_act_map(play_id, acts) do
    # For each act, find all child divisions and map them back to the act
    all_divisions =
      Division
      |> where(play_id: ^play_id)
      |> Repo.all()

    divisions_by_parent = Enum.group_by(all_divisions, & &1.parent_id)

    Enum.reduce(acts, %{}, fn act, acc ->
      children = Map.get(divisions_by_parent, act.id, [])
      child_ids = Enum.map(children, & &1.id)
      all_ids = [act.id | child_ids]
      Enum.reduce(all_ids, acc, fn id, a -> Map.put(a, id, act.number || act.position) end)
    end)
  end

  defp compute_scenes(play_id, acts) do
    scenes =
      Division
      |> where(play_id: ^play_id)
      |> where([d], d.type in @scene_types)
      |> Repo.all()

    scenes_by_parent = Enum.group_by(scenes, & &1.parent_id)

    total = length(scenes)

    per_act =
      Enum.map(acts, fn act ->
        count = length(Map.get(scenes_by_parent, act.id, []))
        %{"act" => act.number || act.position, "count" => count}
      end)

    %{"total" => total, "per_act" => per_act}
  end

  defp count_by_type(elements, type) do
    Enum.count(elements, &(&1.type == type))
  end

  defp verse_distribution(elements, division_to_act, acts) do
    verses = Enum.filter(elements, &(&1.type == "verse_line"))

    by_act =
      Enum.group_by(verses, fn el ->
        Map.get(division_to_act, el.division_id)
      end)

    Enum.map(acts, fn act ->
      num = act.number || act.position
      count = length(Map.get(by_act, num, []))
      %{"act" => num, "count" => count}
    end)
  end

  defp count_split_verses(elements) do
    elements
    |> Enum.filter(&(&1.type == "verse_line" && &1.part in ["I", "M", "F"]))
    |> Enum.count()
  end

  defp count_prose_fragments(elements, division_to_act, acts) do
    prose = Enum.filter(elements, &(&1.type == "prose"))

    by_act =
      Enum.group_by(prose, fn el ->
        Map.get(division_to_act, el.division_id)
      end)

    Enum.map(acts, fn act ->
      num = act.number || act.position
      count = length(Map.get(by_act, num, []))
      %{"act" => num, "count" => count}
    end)
  end

  defp count_asides(elements) do
    Enum.count(elements, & &1.is_aside)
  end

  defp count_aside_verses(elements) do
    elements
    |> Enum.filter(&(&1.type == "verse_line" && &1.is_aside))
    |> Enum.count()
  end

  defp verse_type_distribution(elements) do
    elements
    |> Enum.filter(&(&1.type == "line_group" && &1.verse_type not in [nil, ""]))
    |> Enum.frequencies_by(& &1.verse_type)
    |> Enum.sort_by(fn {_type, count} -> -count end)
    |> Enum.map(fn {type, count} -> %{"verse_type" => type, "count" => count} end)
  end

  defp character_appearances(elements) do
    speeches = Enum.filter(elements, &(&1.type == "speech"))

    # For multi-character speeches, count once per character
    char_counts =
      Enum.flat_map(speeches, fn el ->
        chars = Element.characters(el)

        case chars do
          [] ->
            if el.speaker_label && el.speaker_label != "",
              do: [{el.speaker_label, 1}],
              else: []

          list ->
            Enum.map(list, fn c -> {c.name, 1} end)
        end
      end)
      |> Enum.group_by(fn {name, _} -> name end, fn {_, count} -> count end)
      |> Enum.map(fn {name, counts} -> %{"name" => name, "speeches" => Enum.sum(counts)} end)
      |> Enum.sort_by(fn %{"speeches" => count} -> -count end)

    char_counts
  end
end
