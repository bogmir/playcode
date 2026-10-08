defmodule Playcode.PdfRendererStub do
  @moduledoc """
  Stands in for `Playcode.Export.Pdf` in test, where there is no Chrome. It sends
  `{:rendering, code, self()}` to the `:notify` process and then, by `:mode` in
  `Application.get_env(:playcode, __MODULE__)`:

    * `:ok` (the default) returns a small PDF at once;
    * `:block` waits for `:release` first, as a long render would;
    * `{:error, reason}` fails, and `:raise` raises, as Chrome can.
  """

  def generate(play) do
    config = Application.get_env(:playcode, __MODULE__, [])
    if pid = config[:notify], do: send(pid, {:rendering, play.code, self()})

    case Keyword.get(config, :mode, :ok) do
      :ok ->
        {:ok, pdf(play)}

      :block ->
        receive do
          :release -> {:ok, pdf(play)}
        end

      {:error, reason} ->
        {:error, reason}

      :raise ->
        raise "Chrome went away"
    end
  end

  defp pdf(play), do: "%PDF-1.4 #{play.code} version #{play.content_version}"
end
