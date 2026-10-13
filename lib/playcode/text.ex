defmodule Playcode.Text do
  @moduledoc """
  A text field's whitespace as a TEI file gives it back: a line break (FileMaker's `\\r`,
  a form's `\\r\\n`) is `\\n` with no spaces around it, a run of spaces or tabs is one
  space, and the ends are trimmed. The export writes each `\\n` as `<lb/>`, which the
  import reads back as one.
  """

  @doc "`text` squeezed as above; nil when nothing is left."
  def squeeze(nil), do: nil

  def squeeze(text) do
    text
    |> String.replace(~r/[ \t]*(?:\r\n?|\n)[ \t]*/, "\n")
    |> String.replace(~r/[ \t]+/, " ")
    |> String.trim()
    |> case do
      "" -> nil
      text -> text
    end
  end
end
