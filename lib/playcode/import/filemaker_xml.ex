defmodule Playcode.Import.FilemakerXml do
  @moduledoc """
  Reads one table exported from FileMaker as FMPXMLRESULT: `METADATA/FIELD` names the
  columns, then each `RESULTSET/ROW/COL/DATA` holds one value, in that order. An empty
  column is `<DATA></DATA>`. FileMaker escapes `<<` as `&lt;&lt;`; Saxy decodes it.
  """

  @behaviour Saxy.Handler

  @doc """
  `{:ok, [%{field_name => value}]}`, values trimmed and `""` when empty. With `only`, a
  list of field names, every other column is dropped as it is read: T01's TEI columns make
  its export 180 MB, more than the machine holds beside the app as a parsed tree.
  """
  def read(path, only \\ nil) do
    with {:ok, _stat} <- File.stat(path) do
      state = %{
        root?: false,
        keep: only && MapSet.new(only),
        names: [],
        columns: [],
        row: nil,
        data: nil,
        rows: []
      }

      case Saxy.parse_stream(File.stream!(path, 65_536), __MODULE__, state) do
        {:ok, {:error, _reason} = refused} -> refused
        {:ok, rows} -> {:ok, rows}
        {:error, reason} -> {:error, reason}
      end
    end
  catch
    # Saxy reports a malformed document as an error tuple; this is only for input that is
    # not text at all.
    _kind, reason -> {:error, reason}
  end

  @impl Saxy.Handler
  def handle_event(:start_element, {"FMPXMLRESULT", _attrs}, %{root?: false} = state),
    do: {:ok, %{state | root?: true}}

  def handle_event(:start_element, _element, %{root?: false}),
    do: {:stop, {:error, :not_fmpxmlresult}}

  def handle_event(:start_element, {"FIELD", attrs}, state) do
    {"NAME", name} = List.keyfind(attrs, "NAME", 0)
    {:ok, %{state | names: [name | state.names]}}
  end

  def handle_event(:start_element, {"ROW", _attrs}, state) do
    names = Enum.reverse(state.names)

    {:ok,
     %{state | row: [], columns: Enum.map(names, &{&1, is_nil(state.keep) or &1 in state.keep})}}
  end

  def handle_event(:start_element, {"COL", _attrs}, %{columns: [{_name, keep?} | _]} = state),
    do: {:ok, %{state | data: if(keep?, do: [], else: :dropped)}}

  def handle_event(:characters, text, %{data: data} = state) when is_list(data),
    do: {:ok, %{state | data: [data | text]}}

  def handle_event(:end_element, "DATA", %{data: data} = state) when is_list(data),
    do: {:ok, %{state | data: [data | " "]}}

  def handle_event(:end_element, "COL", %{columns: [{name, keep?} | rest]} = state) do
    row =
      if keep?,
        do: [{name, state.data |> IO.iodata_to_binary() |> String.trim()} | state.row],
        else: state.row

    {:ok, %{state | row: row, data: nil, columns: rest}}
  end

  def handle_event(:end_element, "ROW", state),
    do: {:ok, %{state | rows: [Map.new(state.row) | state.rows]}}

  def handle_event(:end_document, _data, state),
    do: {:ok, Enum.reverse(state.rows)}

  def handle_event(_event, _data, state), do: {:ok, state}

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
end
