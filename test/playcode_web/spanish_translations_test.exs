defmodule PlaycodeWeb.SpanishTranslationsTest do
  @moduledoc """
  Gettext ignores a fuzzy entry, so the page shows the English msgid instead.
  `mix gettext.extract --merge` marks a new message fuzzy when it resembles an old one
  and copies that one's translation, often wrongly: "Add the first editor" became
  "Añadir la primera fuente". Review each one, translate it, and remove the flag.

  The English files are left alone: an English fuzzy entry has an empty msgstr and falls
  back to its msgid, which is the English text.
  """
  use ExUnit.Case, async: true

  test "no Spanish translation is fuzzy" do
    fuzzy =
      for path <- Path.wildcard("priv/gettext/es/LC_MESSAGES/*.po"),
          message <- Expo.PO.parse_file!(path).messages,
          Expo.Message.has_flag?(message, "fuzzy"),
          do: "#{Path.basename(path)}: #{IO.iodata_to_binary(message.msgid)}"

    assert fuzzy == []
  end
end
