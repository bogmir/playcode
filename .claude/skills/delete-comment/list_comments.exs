# Lists each comment block of the given files, with the code line after it.
for path <- System.argv() do
  src = File.read!(path)
  lines = String.split(src, "\n") |> List.to_tuple()
  {:ok, _, comments} = Code.string_to_quoted_with_comments(src, columns: true)
  comments
  |> Enum.chunk_while([], fn c, acc ->
    case acc do
      [p | _] when p.line + 1 == c.line -> {:cont, [c | acc]}
      [] -> {:cont, [c]}
      _ -> {:cont, Enum.reverse(acc), [c]}
    end
  end, fn [] -> {:cont, []}; acc -> {:cont, Enum.reverse(acc), []} end)
  |> Enum.each(fn [first | _] = block ->
    last = List.last(block)
    next = if last.line < tuple_size(lines), do: elem(lines, last.line) |> String.trim(), else: ""
    IO.puts("#{path}:#{first.line}")
    Enum.each(block, &IO.puts("  " <> &1.text))
    IO.puts("  => " <> String.slice(next, 0, 100))
  end)
end
