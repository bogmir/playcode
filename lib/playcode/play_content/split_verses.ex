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
end
