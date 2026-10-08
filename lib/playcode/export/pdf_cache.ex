defmodule Playcode.Export.PdfCache do
  @moduledoc """
  A play's PDF, rendered once per version and kept on disk.

  `Playcode.Export.Pdf` goes through headless Chrome, one PDF at a time, and takes from
  seconds to well over a minute for the longest plays: the time grows with the square of
  the play's length. So each version is rendered once, by a task of its own, and saved
  under `dir/0` as `<play id>-<content_version>-<code>.pdf`. `content_version` moves
  whenever anything the play shows changes, and `<code>` whenever the export's code does,
  so a stale file is never served; a new file replaces the play's older ones.

  `fetch/1` waits for a render at most `:pdf_wait` (50 seconds, inside Fly's 60-second
  idle cut) and then answers `{:error, :pending}`: the render goes on, and a later request
  gets the file. Requests for a play being rendered wait on that one render. Each render
  starts a Chrome of its own (ChromicPDF's `on_demand`), so at most `:pdf_max_renders`
  plays render at once, one by default: two Chromes do not fit the 1 GB machine. Past
  that, a new play gets `{:error, :busy}` rather than a place in a queue of hours.

  Every render is logged with its duration and outcome, apart from the cache hits: they
  are the numbers to argue for more compute with.
  """
  use GenServer

  require Logger

  alias Playcode.Catalogue.Play

  @default_wait 50_000
  @default_max_renders 1

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Where the PDFs are kept: `:pdf_cache_dir`, on the volume in production."
  def dir do
    Application.get_env(:playcode, :pdf_cache_dir, Path.join(System.tmp_dir!(), "playcode-pdf"))
  end

  @doc """
  The path of `play`'s PDF, rendering it first if this version has none:
  `{:ok, path}`, or `{:error, :pending | :busy | reason}`.
  """
  def fetch(%Play{} = play) do
    path = path(play)

    if File.exists?(path) do
      {:ok, path}
    else
      try do
        GenServer.call(__MODULE__, {:fetch, play, path}, wait())
      catch
        :exit, {:timeout, _} -> {:error, :pending}
      end
    end
  end

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def handle_call({:fetch, play, path}, from, renders) do
    cond do
      File.exists?(path) ->
        {:reply, {:ok, path}, renders}

      Map.has_key?(renders, path) ->
        {:noreply, Map.update!(renders, path, &%{&1 | waiters: [from | &1.waiters]})}

      map_size(renders) >= max_renders() ->
        {:reply, {:error, :busy}, renders}

      true ->
        task =
          Task.Supervisor.async_nolink(Playcode.Export.PdfCache.Tasks, fn ->
            render(play, path)
          end)

        {:noreply, Map.put(renders, path, %{ref: task.ref, waiters: [from]})}
    end
  end

  @impl true
  def handle_info({ref, result}, renders) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    {:noreply, finish(renders, ref, result)}
  end

  # A render task that died without answering (it rescues what it can).
  def handle_info({:DOWN, ref, :process, _pid, reason}, renders) do
    {:noreply, finish(renders, ref, {:error, reason})}
  end

  defp finish(renders, ref, result) do
    case Enum.find(renders, fn {_path, render} -> render.ref == ref end) do
      {path, render} ->
        Enum.each(render.waiters, &GenServer.reply(&1, result))
        Map.delete(renders, path)

      nil ->
        renders
    end
  end

  defp render(play, path) do
    started = System.monotonic_time(:millisecond)

    result =
      try do
        renderer().generate(play)
      rescue
        exception -> {:error, exception}
      end

    seconds = Float.round((System.monotonic_time(:millisecond) - started) / 1000, 1)

    case result do
      {:ok, pdf} ->
        save(play, path, pdf)
        Logger.info("PDF #{play.code}: rendered in #{seconds} s, #{div(byte_size(pdf), 1024)} KB")
        {:ok, path}

      {:error, reason} ->
        Logger.warning("PDF #{play.code}: failed after #{seconds} s: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Written aside and renamed, so a reader never sees half a file; then the play's
  # older versions go.
  defp save(play, path, pdf) do
    File.mkdir_p!(dir())
    tmp = path <> ".#{System.unique_integer([:positive])}.tmp"
    File.write!(tmp, pdf)
    File.rename!(tmp, path)

    for old <- Path.wildcard(Path.join(dir(), "#{play.id}-*.pdf")), old != path, do: File.rm(old)
  end

  defp path(play) do
    Path.join(dir(), "#{play.id}-#{play.content_version}-#{code_version()}.pdf")
  end

  # What the PDF is rendered with: the HTML export and the PDF export around it, and the
  # modules that draw the text and the notes in it.
  defp code_version do
    [
      Playcode.Export.Html,
      Playcode.Export.Pdf,
      Playcode.Export.NoteMarkup,
      Playcode.PlayContent.InlineMarkup,
      Playcode.PlayContent.Note
    ]
    |> Enum.map(& &1.module_info(:md5))
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 12)
  end

  defp renderer, do: Application.get_env(:playcode, :pdf_renderer, Playcode.Export.Pdf)
  defp wait, do: Application.get_env(:playcode, :pdf_wait, @default_wait)
  defp max_renders, do: Application.get_env(:playcode, :pdf_max_renders, @default_max_renders)
end
