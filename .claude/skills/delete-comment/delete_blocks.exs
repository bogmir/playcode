# Deletes whole comment blocks. TARGETS holds lines "path start_line start_line ...",
# each start_line the first line of a block as list_comments.exs printed it.
[targets] = System.argv()
for line <- File.read!(targets) |> String.split("\n", trim: true) do
  [path | starts] = String.split(line)
  starts = Enum.map(starts, &String.to_integer/1)
  src = File.read!(path)
  {:ok, _, comments} = Code.string_to_quoted_with_comments(src)
  lines = String.split(src, "\n")
  comment_lines = MapSet.new(comments, & &1.line)
  drop =
    Enum.flat_map(starts, fn s ->
      unless MapSet.member?(comment_lines, s), do: raise("#{path}:#{s} is no comment")
      Stream.iterate(s, &(&1 + 1)) |> Enum.take_while(&(MapSet.member?(comment_lines, &1) and String.trim_leading(Enum.at(lines, &1 - 1)) |> String.starts_with?("#")))
    end)
    |> MapSet.new()
  kept = lines |> Enum.with_index(1) |> Enum.reject(fn {_, i} -> i in drop end) |> Enum.map(&elem(&1, 0))
  File.write!(path, Enum.join(kept, "\n"))
  IO.puts("#{path}: -#{MapSet.size(drop)}")
end
