defmodule Playcode.Import.FilemakerXml do
  @moduledoc """
  Reads one table exported from FileMaker as FMPXMLRESULT: `METADATA/FIELD` names the
  columns, then each `RESULTSET/ROW/COL/DATA` holds one value, in that order. An empty
  column is `<DATA></DATA>`. FileMaker escapes `<<` as `&lt;&lt;`; Saxy decodes it.
  """

  @doc "`{:ok, [%{field_name => value}]}`, values trimmed and `\"\"` when empty."
  def read(path) do
    with {:ok, xml} <- File.read(path),
         {:ok, {"FMPXMLRESULT", _attrs, children}} <- parse(xml) do
      names =
        children |> child("METADATA") |> elements("FIELD") |> Enum.map(&attribute(&1, "NAME"))

      rows =
        children
        |> child("RESULTSET")
        |> elements("ROW")
        |> Enum.map(fn row ->
          names |> Enum.zip(row |> elements("COL") |> Enum.map(&value/1)) |> Map.new()
        end)

      {:ok, rows}
    else
      {:ok, _other_root} -> {:error, :not_fmpxmlresult}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Reads each of `files` (`[key: file_name]`) from `dir`: `{:ok, %{key => rows}}`, or
  `{:error, {file, reason}}` for the first that cannot be read.
  """
  def read_tables(dir, files) do
    Enum.reduce_while(files, {:ok, %{}}, fn {key, file}, {:ok, data} ->
      case read(Path.join(dir, file)) do
        {:ok, rows} -> {:cont, {:ok, Map.put(data, key, rows)}}
        {:error, reason} -> {:halt, {:error, {file, reason}}}
      end
    end)
  end

  @doc "The play code FileMaker's version id stands for: 38 is EMOTHE0038; nil for an id that is no number."
  def version_code(version) do
    case Integer.parse(version || "") do
      {number, ""} -> "EMOTHE" <> String.pad_leading(Integer.to_string(number), 4, "0")
      _other -> nil
    end
  end

  defp parse(xml) do
    Saxy.SimpleForm.parse_string(xml)
  catch
    # Saxy reports a malformed document as an error tuple; this is only for input that is
    # not text at all.
    _kind, reason -> {:error, reason}
  end

  defp child(children, name), do: Enum.find(children, &match?({^name, _attrs, _children}, &1))

  defp elements(nil, _name), do: []

  defp elements({_name, _attrs, children}, name),
    do: Enum.filter(children, &match?({^name, _attrs, _children}, &1))

  defp attribute({_name, attrs, _children}, key) do
    {^key, value} = List.keyfind(attrs, key, 0)
    value
  end

  defp value(col) do
    col
    |> elements("DATA")
    |> Enum.map_join(" ", fn {_name, _attrs, children} ->
      children |> Enum.filter(&is_binary/1) |> Enum.join()
    end)
    |> String.trim()
  end
end
