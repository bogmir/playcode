defmodule Playcode.Witnesses do
  @moduledoc """
  A play's witnesses (S3): the manuscripts and early printings its text survives in.
  Spec: docs/superpowers/specs/2026-10-10-s3-witnesses-design.md.

  The printed line (`parts/1`, `plain/1`, `html/1`) is emothe.uv.es's, and the admin
  preview, `/plays/:code` and the static site all print through it. `xml_id/1` and
  `tei_type/1` are the TEI export's and import's, so the `<app>` work can point `wit` at
  the same id.
  """

  import Ecto.Query
  import Ecto.Changeset, only: [change: 2, get_field: 2, put_change: 3]

  alias Playcode.Bibliography.{Entry, Link}
  alias Playcode.PlayContent.InlineMarkup
  alias Playcode.Repo
  alias Playcode.Witnesses.Witness

  @doc "The play's witnesses, in order."
  def list_for_play(play_id) do
    Witness
    |> where([w], w.play_id == ^play_id)
    |> order_by([w], asc: w.position, asc: w.inserted_at)
    |> Repo.all()
  end

  @doc """
  The play's witness `id`, or nil. Scoped to the play because the id arrives from the
  browser: another play's witness, a deleted one or a malformed id is nil.
  """
  def get_witness(play_id, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Repo.get_by(Witness, id: id, play_id: play_id)
      :error -> nil
    end
  end

  def change_witness(%Witness{} = witness, attrs \\ %{}), do: Witness.changeset(witness, attrs)

  @doc """
  Adds a witness after the play's last. `attrs` carry its `play_id`; `base` is the struct
  to start from, so the FileMaker import can set `filemaker_id`.
  """
  def create_witness(attrs, %Witness{} = base \\ %Witness{}) do
    changeset = Witness.changeset(base, attrs)

    changeset
    |> put_change(:position, next_position(get_field(changeset, :play_id)))
    |> Repo.insert()
  end

  def update_witness(%Witness{} = witness, attrs),
    do: witness |> Witness.changeset(attrs) |> Repo.update()

  def delete_witness(%Witness{} = witness), do: Repo.delete(witness)

  @doc "Swaps a witness with its neighbour and renumbers the play's. A move past either end is a no-op."
  def move_witness(%Witness{} = witness, direction) when direction in [:up, :down] do
    witnesses = list_for_play(witness.play_id)
    index = Enum.find_index(witnesses, &(&1.id == witness.id))
    target = if direction == :up, do: index && index - 1, else: index && index + 1

    if is_nil(index) or target < 0 or target >= length(witnesses) do
      :ok
    else
      {:ok, :ok} =
        Repo.transaction(fn ->
          witnesses
          |> List.replace_at(index, Enum.at(witnesses, target))
          |> List.replace_at(target, Enum.at(witnesses, index))
          |> Enum.with_index()
          |> Enum.each(fn {w, i} ->
            if w.position != i, do: Repo.update!(change(w, position: i))
          end)
        end)

      :ok
    end
  end

  @doc """
  The sigla a TEI import must not bring in for the play: its witnesses' (the file's own
  are removed before a re-import reads them) and its modern editions', which live in the
  bibliography.
  """
  def taken_sigla(play_id) do
    witnesses =
      from(w in Witness, where: w.play_id == ^play_id and not is_nil(w.siglum), select: w.siglum)

    editions =
      from(l in Link,
        join: e in Entry,
        on: e.id == l.entry_id,
        where: l.play_id == ^play_id and not is_nil(e.siglum),
        select: e.siglum
      )

    MapSet.new(Repo.all(witnesses) ++ Repo.all(editions))
  end

  # FileMaker's T03.1 leaves as TEI's {bibl@type, bibl@subtype}, in its own Spanish terms,
  # as S4's biblStruct types are.
  @tei_types %{
    "manuscript" => {"manuscrito", nil},
    "autograph" => {"manuscrito", "autografo"},
    "copy" => {"manuscrito", "copia"},
    "early_edition" => {"edicion_antigua", nil},
    "collection" => {"edicion_antigua", "coleccion"},
    "collection_single_author" => {"edicion_antigua", "coleccion_de_autor"},
    "collection_several_authors" => {"edicion_antigua", "coleccion_de_diversos_autores"},
    "loose" => {"edicion_antigua", "suelta"}
  }

  @doc """
  The witness as `%{text: binary, italic: boolean}` segments, emothe.uv.es's line:
  `<<Title>>. [Normalised title]. Attribution. City. Publisher. Date. Format. Note.
  Archivo: Shelfmark.` An empty field drops out with its full stop, a value ending in `.`,
  `?` or `!` gets no second one, and whitespace is collapsed. `Archivo:` is FileMaker's
  label and is not translated.
  """
  def parts(%Witness{} = w) do
    [
      wrap(w.title && String.replace(w.title, ["<<", ">>"], ""), "<<", ">>"),
      wrap(w.normalized_title, "[", "]"),
      clean(w.attribution),
      clean(w.pub_place),
      clean(w.publisher),
      clean(w.date),
      clean(w.format),
      clean(w.note),
      wrap(w.shelfmark, "Archivo: ", "")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.map_join(" ", &stop/1)
    |> InlineMarkup.parts()
  end

  @doc "The witness as plain text."
  def plain(%Witness{} = w), do: w |> parts() |> Enum.map_join(& &1.text)

  @doc "The witness as safe HTML: `<em>` for the italics, the rest escaped."
  def html(%Witness{} = w) do
    {:safe,
     w
     |> parts()
     |> Enum.map(fn
       %{text: text, italic: true} -> ["<em>", escape(text), "</em>"]
       %{text: text} -> escape(text)
     end)}
  end

  @doc "A witness type as TEI's `{bibl@type, bibl@subtype}`; nil for none."
  def tei_type(type), do: @tei_types[type]

  @doc "The witness type a `<bibl type subtype>` names, or nil."
  def type_from_tei(type, subtype) do
    Enum.find_value(@tei_types, fn {key, pair} -> if pair == {type, subtype}, do: key end)
  end

  @doc """
  The witness's `xml:id`: its siglum when that is an XML name, else `wit-` and the siglum
  with anything a name cannot hold made `_` (EMOTHE0530's `1623b`). Nil without a siglum.
  The siglum itself always travels verbatim as `@n`.
  """
  def xml_id(%{siglum: nil}), do: nil

  def xml_id(%{siglum: siglum}) do
    # ponytail: letters, digits, `.`, `-`, `_`; XML's NameChar allows a few more
    # (combining marks, `·`), which no siglum in the corpus uses.
    if siglum =~ ~r/\A[\p{L}_][\p{L}\p{N}._-]*\z/u,
      do: siglum,
      else: "wit-" <> String.replace(siglum, ~r/[^\p{L}\p{N}._-]/u, "_")
  end

  defp wrap(value, open, close) do
    case clean(value) do
      nil -> nil
      text -> open <> text <> close
    end
  end

  defp clean(nil), do: nil

  defp clean(text) do
    case text |> String.replace(~r/\s+/u, " ") |> String.trim() do
      "" -> nil
      text -> text
    end
  end

  # "Denmarke.>>" ends its sentence inside the italics, so the stop is looked for before them.
  defp stop(text) do
    if text |> String.trim_trailing(">>") |> String.ends_with?([".", "?", "!"]),
      do: text,
      else: text <> "."
  end

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  # max + 1, not a count: a deletion leaves a gap, and a count would tie the next witness
  # with the one after the gap.
  defp next_position(nil), do: 0

  defp next_position(play_id) do
    case Repo.aggregate(from(w in Witness, where: w.play_id == ^play_id), :max, :position) do
      nil -> 0
      max -> max + 1
    end
  end
end
