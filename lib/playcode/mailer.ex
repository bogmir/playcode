defmodule Playcode.Mailer do
  @moduledoc false

  use Swoosh.Mailer, otp_app: :playcode

  require Logger

  @failures ["rejected", "TLS failed"]

  @doc """
  gen_smtp's `trace_fun`: logs the steps where the relay refused, with its reply.

  Chosen by the format, never the formatted text: other steps print the options, password
  included.
  """
  def log_smtp_failure(format, args) do
    if String.contains?(to_string(format), @failures) do
      message = format |> :io_lib.format(args) |> IO.chardata_to_string() |> String.trim()
      Logger.error("SMTP #{message}")
    end
  end
end
