defmodule PlaycodeWeb.ErrorTranslationsTest do
  # A changeset message is a plain string, so `mix gettext.extract` never sees it:
  # each one has to be added to `errors.pot` and translated by hand. This test
  # finds them in the source so a new one cannot ship in English on a Spanish page.
  use ExUnit.Case, async: true

  @custom_message ~r/(?:add_error\([^"()]*|message: )"([^"]+)"/

  test "every custom changeset message has a Spanish translation" do
    messages =
      for path <- Path.wildcard("lib/**/*.ex"),
          [_, msg] <- Regex.scan(@custom_message, File.read!(path)),
          uniq: true,
          do: msg

    assert "must be given together with the end year" in messages

    untranslated =
      Gettext.with_locale(PlaycodeWeb.Gettext, "es", fn ->
        Enum.filter(messages, &(Gettext.dgettext(PlaycodeWeb.Gettext, "errors", &1) == &1))
      end)

    assert untranslated == []
  end
end
