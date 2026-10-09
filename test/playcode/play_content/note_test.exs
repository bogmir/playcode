defmodule Playcode.PlayContent.NoteTest do
  @moduledoc """
  `Note.glossed/2` directly: which word a note glosses is decided by word boundaries in
  the plain text, which the Notes pages (`static_site_play_test.exs`,
  `play_show_live_test.exs`) show for one or two cases only.
  """
  use ExUnit.Case, async: true

  alias Playcode.PlayContent.Note

  defp note(offset, term \\ nil), do: %Note{offset: offset, term: term, body: "Glosa."}

  test "the term, when the note has one" do
    assert Note.glossed(note(10, "voyent"), "Nous voyent dans la ville") == "voyent"
  end

  test "otherwise the last word before the note, punctuation between or not" do
    text = "Ni un ratón se ha movido."

    assert Note.glossed(note(String.length("Ni un ratón")), text) == "ratón"
    assert Note.glossed(note(String.length(text)), text) == "movido"
    assert Note.glossed(note(String.length("Ni un rat")), text) == "rat"
  end

  test "counts the offset in the plain text, italics and stage markers left out" do
    text = "Dijo <<adiós>> <stage>(bajo)</stage> y salió"

    assert Note.glossed(note(String.length("Dijo adiós")), text) == "adiós"
    assert Note.glossed(note(String.length("Dijo adiós (bajo)")), text) == "bajo"
  end

  test "keeps an apostrophe inside a word" do
    assert Note.glossed(note(String.length("Thou art d'Artagnan")), "Thou art d'Artagnan") ==
             "d'Artagnan"
  end

  test "none at the start of the text, a blank term, or no text" do
    assert Note.glossed(note(0), "Hola") == nil
    assert Note.glossed(note(4, ""), "Hola") == "Hola"
    assert Note.glossed(note(0), nil) == nil
  end
end
