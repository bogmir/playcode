defmodule Playcode.PlayContent.SplitVerses do
  @moduledoc """
  A split verse's parts in reading order: a first part opens it, middle parts carry it on,
  a last part closes it. TEI's schema checks a part's value, not this order, and the
  Content tab's form takes any part anywhere, so the import preview and the Content tab
  both list the parts that break it, and neither refuses them.
  """

  @doc """
  The parts out of order in `acts`, each an act's verse lines in reading order (its own,
  then its scenes'), as `{line, problem}`: `:completes_nothing` for a middle or last part
  with no verse open, `:never_completed` for a first part no last part closes. Checked act
  by act: a split verse crosses scenes (164 times in the corpus), never acts.
  """
  def out_of_order(acts), do: Enum.flat_map(acts, &in_act/1)

  defp in_act(lines) do
    {problems, open} =
      Enum.reduce(lines, {[], nil}, fn line, {problems, open} ->
        case {line.part, open} do
          {"I", _} -> {never_completed(problems, open), line}
          {part, nil} when part in ["M", "F"] -> {[{line, :completes_nothing} | problems], nil}
          {"M", _} -> {problems, open}
          {"F", _} -> {problems, nil}
          _whole -> {never_completed(problems, open), nil}
        end
      end)

    Enum.reverse(never_completed(problems, open))
  end

  defp never_completed(problems, nil), do: problems
  defp never_completed(problems, line), do: [{line, :never_completed} | problems]

  @doc """
  What lines up each later part of a shared line where the one before it ended, from
  `lines`, verse lines in reading order: `%{id => %{lead: …, line: …}}` for each middle or
  last part with an earlier one, `lead` the earlier parts' content, `line` every part's.
  A part with nothing open before it (an orphan) has no entry.
  """
  def leads(lines) do
    {groups, open} =
      Enum.reduce(lines, {[], []}, fn line, {groups, open} ->
        case {line.part, open} do
          {"I", _} -> {close(groups, open), [line]}
          {"M", [_ | _]} -> {groups, [line | open]}
          {"F", [_ | _]} -> {close(groups, [line | open]), []}
          _ -> {close(groups, open), []}
        end
      end)

    for parts <- close(groups, open),
        whole = Enum.map_join(parts, " ", & &1.content),
        {part, i} <- Enum.with_index(parts),
        i > 0,
        into: %{},
        do:
          {part.id,
           %{lead: parts |> Enum.take(i) |> Enum.map_join(" ", & &1.content), line: whole}}
  end

  defp close(groups, []), do: groups
  defp close(groups, open), do: [Enum.reverse(open) | groups]
end
