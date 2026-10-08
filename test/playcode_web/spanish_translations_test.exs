defmodule PlaycodeWeb.SpanishTranslationsTest do
  @moduledoc """
  Guards the Spanish translations against `fuzzy` entries.

  A PO entry pairs a msgid, the English text in the code, with a msgstr, its Spanish.
  When `mix gettext.extract --merge` meets a new msgid that looks like an old one, it
  copies the old msgstr and flags the entry fuzzy, meaning "a guess, check me":

      #, elixir-autogen, elixir-format, fuzzy
      msgid "Add the first editor"
      msgstr "Añadir la primera fuente"

  Gettext never uses a fuzzy msgstr, so the page shows the English msgid, and the guess
  is often wrong anyway: this one says "source". 29 had piled up unnoticed.

  When this test fails, open `priv/gettext/es/LC_MESSAGES/default.po`, find each msgid it
  lists, write the right Spanish and delete `, fuzzy` from the line above it.

  The English files are left alone: an English msgstr is empty, so it falls back to the
  msgid, which is already the English text.
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
