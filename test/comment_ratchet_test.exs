defmodule CommentRatchetTest do
  @moduledoc """
  Comments in lib/ only go down. A file may hold as many comments (`#` lines and HEEx
  `<%!-- --%>`) as `comment_baseline.txt` grants it, and a file it does not list none. A
  file holding fewer lowers its line, so a deleted comment cannot come back unseen.

  `UPDATE_COMMENT_BASELINE=1 mix test test/comment_ratchet_test.exs` rewrites the baseline
  from lib/ as it stands; the diff of that file is where a new comment is argued for.
  """
  use ExUnit.Case, async: true

  @baseline Path.expand("comment_baseline.txt", __DIR__)

  setup_all do
    if System.get_env("UPDATE_COMMENT_BASELINE"), do: write_baseline(counts())
    %{counts: counts(), baseline: read_baseline()}
  end

  test "no file in lib/ holds more comments than the baseline grants it", ctx do
    over =
      for {path, n} <- ctx.counts, n > Map.get(ctx.baseline, path, 0) do
        "#{path}: #{n}, baseline #{Map.get(ctx.baseline, path, 0)}"
      end

    assert over == [], """
    Comments added in lib/. Say it in the code (a name, a function, a test) instead; a
    comment only for what the code cannot show, with the baseline raised in the same commit:

    #{Enum.join(over, "\n")}
    """
  end

  test "the baseline is lowered as comments go", ctx do
    loose =
      for {path, n} <- ctx.baseline, Map.get(ctx.counts, path, 0) < n do
        "#{path}: #{Map.get(ctx.counts, path, 0)}, baseline #{n}"
      end

    assert loose == [], """
    Fewer comments than the baseline grants: lower it (UPDATE_COMMENT_BASELINE=1).

    #{Enum.join(loose, "\n")}
    """
  end

  defp counts do
    for path <- Path.wildcard("lib/**/*.{ex,heex}"), n = comments(path), n > 0, into: %{} do
      {path, n}
    end
  end

  # HEEx comments sit inside ~H strings, where the Elixir parser sees no comment.
  defp comments(path) do
    source = File.read!(path)
    heex = length(Regex.scan(~r/<%!--/, source))

    if String.ends_with?(path, ".heex") do
      heex
    else
      {_quoted, comments} = Code.string_to_quoted_with_comments!(source)
      heex + length(comments)
    end
  end

  defp read_baseline do
    case File.read(@baseline) do
      {:ok, text} ->
        for line <- String.split(text, "\n", trim: true), into: %{} do
          [path, n] = String.split(line)
          {path, String.to_integer(n)}
        end

      {:error, :enoent} ->
        %{}
    end
  end

  defp write_baseline(counts) do
    lines = for {path, n} <- Enum.sort(counts), do: "#{path} #{n}\n"
    File.write!(@baseline, lines)
  end
end
