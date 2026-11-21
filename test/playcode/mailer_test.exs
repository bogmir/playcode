defmodule Playcode.MailerTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Playcode.Mailer

  # gen_smtp reports a refused login as {:network_failure, host, {:error, :closed}}: it tries
  # the next login method on the connection the relay has already closed. Gmail's reply
  # (2026-11-21, a revoked app password) reached no log.
  test "a relay's refusal reaches the log with its reply" do
    log =
      capture_log(fn ->
        Mailer.log_smtp_failure(~c"password rejected: ~s", [
          "535-5.7.8 Username and Password not accepted"
        ])
      end)

    assert log =~ "535-5.7.8 Username and Password not accepted"
  end

  test "a step that prints the options, password included, is never logged" do
    log =
      capture_log(fn ->
        Mailer.log_smtp_failure(~c"TLS not requested ~p~n", [[password: "s3cret"]])
      end)

    refute log =~ "s3cret"
  end
end
