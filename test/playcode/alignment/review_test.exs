defmodule Playcode.Alignment.ReviewTest do
  @moduledoc """
  The pair review's rows travel from a background task to the page's process, and a
  message copies every term in full: a row holding its act's division would copy the
  whole act once per row (4.7 GB for 0084). So a row holds only what the page prints.
  """
  use Playcode.DataCase, async: true

  import Playcode.ImportHelpers

  alias Playcode.Alignment.Review
  alias Playcode.PlayContent

  test "a row holds only what the page prints, no division or element" do
    %{original: original, french: french} = split_speech_editions()

    rows =
      Review.rows(
        PlayContent.load_speeches(original.id),
        PlayContent.load_speeches(french.id)
      )

    assert [%{place: "ACT I", original: %{speaker: "ANTONY", opening: "One."}} | _] = rows

    refute Enum.any?(rows, fn row ->
             Enum.any?([row.place, row.original, row.translation], &is_struct/1)
           end)
  end
end
