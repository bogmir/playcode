defmodule PlaycodeWeb.Components.PlayText do
  @moduledoc """
  Components for rendering play text: speeches, verse lines, stage directions.
  Styled to match the production EMOTHE/Artelope color scheme and fonts.
  """
  use Phoenix.Component
  use Gettext, backend: PlaycodeWeb.Gettext

  alias Playcode.PlayContent
  alias Playcode.PlayContent.{Division, InlineMarkup, Note}
  alias PlaycodeWeb.PlayLabels

  attr :divisions, :list, required: true
  attr :characters, :list, default: []
  attr :show_line_numbers, :boolean, default: true
  attr :show_stage_directions, :boolean, default: true
  attr :show_asides, :boolean, default: true
  attr :show_split_verses, :boolean, default: true
  attr :show_verse_type, :boolean, default: false
  attr :sync_keys, :boolean, default: false

  def play_body(assigns) do
    ~H"""
    <div class="play-text">
      <div
        :for={{division, div_key} <- sync_keyed(@divisions, @sync_keys)}
        class="mb-8 scroll-mt-16"
        id={"div-#{division.id}"}
      >
        <.division_heading division={division} sync_key={div_key} />

        <%!-- Render inline cast list for elenco divisions --%>
        <.cast_list :if={division.type == "elenco"} characters={@characters} />

        <div :if={Map.has_key?(division, :loaded_elements)}>
          <.element_list
            elements={Map.get(division, :loaded_elements, [])}
            show_line_numbers={@show_line_numbers}
            show_stage_directions={@show_stage_directions}
            show_asides={@show_asides}
            show_split_verses={@show_split_verses}
            show_verse_type={@show_verse_type}
            act_key={div_key}
          />
        </div>

        <div
          :for={{child, child_key} <- sync_keyed(Map.get(division, :children, []), @sync_keys)}
          class="mb-6 scroll-mt-16"
          id={"div-#{child.id}"}
        >
          <.division_heading division={child} sync_key={child_key && "#{div_key}/#{child_key}"} />
          <div :if={Map.has_key?(child, :loaded_elements)}>
            <.element_list
              elements={Map.get(child, :loaded_elements, [])}
              show_line_numbers={@show_line_numbers}
              show_stage_directions={@show_stage_directions}
              show_asides={@show_asides}
              show_split_verses={@show_split_verses}
              show_verse_type={@show_verse_type}
              act_key={div_key}
            />
          </div>
        </div>
      </div>
      <.endnotes notes={Note.reading_order(@divisions)} />
    </div>
    """
  end

  # Each division with its comparison key (see `Division.sync_keys/1`), or with nil when
  # the page does not sync. A speech carries its act's key, whatever scene it is in:
  # editions often split an act into scenes differently.
  defp sync_keyed(divisions, true), do: Enum.zip(divisions, Division.sync_keys(divisions))
  defp sync_keyed(divisions, false), do: Enum.map(divisions, &{&1, nil})

  @act_types ~w(acto act acte jornada play)

  attr :division, :map, required: true
  attr :sync_key, :string, default: nil

  defp division_heading(assigns) do
    assigns = assign(assigns, :is_act, assigns.division.type in @act_types)

    ~H"""
    <h2
      :if={@division.title && @is_act}
      class="font-bold text-center my-6 text-lg uppercase tracking-wide play-act-title"
      data-sync-div={@sync_key}
    >
      <.inline_content text={@division.title} notes={@division.notes} />
    </h2>
    <h3
      :if={@division.title && !@is_act}
      class="font-semibold text-center my-4 text-xs uppercase tracking-widest play-scene-title"
      data-sync-div={@sync_key}
    >
      <.inline_content text={@division.title} notes={@division.notes} />
    </h3>
    """
  end

  attr :characters, :list, required: true

  defp cast_list(assigns) do
    visible = Enum.filter(assigns.characters, &(!&1.is_hidden))
    assigns = assign(assigns, :visible_characters, visible)

    ~H"""
    <div :if={@visible_characters != []} class="cast-list mb-8 max-w-xl mx-auto">
      <div
        :for={char <- @visible_characters}
        class="cast-item flex items-baseline gap-3 py-1 ml-1 sm:ml-4"
      >
        <span class="speaker shrink-0">{char.name}</span>
        <span
          :if={char.description}
          class="text-sm"
          style="color: oklch(from var(--color-base-content) l c h / 0.55)"
        >
          {char.description}
        </span>
      </div>
    </div>
    """
  end

  attr :elements, :list, required: true
  attr :show_line_numbers, :boolean, default: true
  attr :show_stage_directions, :boolean, default: true
  attr :show_asides, :boolean, default: true
  attr :show_split_verses, :boolean, default: true
  attr :show_verse_type, :boolean, default: false
  attr :act_key, :string, default: nil

  defp element_list(assigns) do
    ~H"""
    <div>
      <div :for={element <- @elements}>
        <.render_element
          element={element}
          show_line_numbers={@show_line_numbers}
          show_stage_directions={@show_stage_directions}
          show_asides={@show_asides}
          show_split_verses={@show_split_verses}
          show_verse_type={@show_verse_type}
          act_key={@act_key}
        />
      </div>
    </div>
    """
  end

  attr :element, :map, required: true
  attr :show_line_numbers, :boolean, default: true
  attr :show_stage_directions, :boolean, default: true
  attr :show_asides, :boolean, default: true
  attr :show_split_verses, :boolean, default: true
  attr :show_verse_type, :boolean, default: false
  attr :act_key, :string, default: nil

  defp render_element(%{element: %{type: "speech"}} = assigns) do
    ~H"""
    <div
      :if={!@element.is_aside || @show_asides}
      class={["speech mt-3 mb-5", @element.is_aside && "pl-6 aside-border"]}
      data-sync-act={@act_key}
    >
      <div :if={@element.speaker_label} class="speaker mb-1">
        <.inline_content text={@element.speaker_label} notes={@element.notes} />
      </div>
      <div :for={child <- Map.get(@element, :children, [])}>
        <.render_element
          element={child}
          show_line_numbers={@show_line_numbers}
          show_stage_directions={@show_stage_directions}
          show_asides={@show_asides}
          show_split_verses={@show_split_verses}
          show_verse_type={@show_verse_type}
          act_key={@act_key}
        />
      </div>
    </div>
    """
  end

  defp render_element(%{element: %{type: "line_group"}} = assigns) do
    ~H"""
    <div class="line-group">
      <div
        :if={@show_verse_type && @element.verse_type}
        class="flex items-baseline gap-2 ml-1 sm:ml-4 -mb-0.5"
      >
        <span class="flex-1" />
        <span class="w-8 sm:w-16 text-left text-[9px] italic text-base-content/35 shrink-0 leading-tight">
          {@element.verse_type}
        </span>
      </div>
      <div :for={child <- Map.get(@element, :children, [])}>
        <.render_element
          element={child}
          show_line_numbers={@show_line_numbers}
          show_stage_directions={@show_stage_directions}
          show_asides={@show_asides}
          show_split_verses={@show_split_verses}
          show_verse_type={@show_verse_type}
          act_key={@act_key}
        />
      </div>
    </div>
    """
  end

  defp render_element(%{element: %{type: "verse_line"}} = assigns) do
    ~H"""
    <div class="verse-line flex items-baseline gap-1 sm:gap-2 ml-1 sm:ml-4">
      <span class={[
        "flex-1",
        @element.rend == "indent" && "pl-8",
        @show_split_verses && @element.part == "F" && "part-f",
        @show_split_verses && @element.part == "M" && "part-m"
      ]}>
        <.inline_content
          text={@element.content}
          notes={@element.notes}
          show_stage={@show_stage_directions}
        />
      </span>
      <span
        :if={@element.line_number}
        class={[
          "line-number w-8 sm:w-16 text-left shrink-0 select-none",
          !@show_line_numbers && "invisible"
        ]}
      >
        {@element.line_number}
      </span>
      <span
        :if={!@element.line_number}
        class="w-8 sm:w-16 shrink-0"
      />
    </div>
    """
  end

  defp render_element(%{element: %{type: "stage_direction"}} = assigns) do
    ~H"""
    <div :if={@show_stage_directions} class="stage-direction text-center my-4 px-2 sm:px-8">
      (<.inline_content text={@element.content} notes={@element.notes} />)
    </div>
    """
  end

  defp render_element(%{element: %{type: "prose"}} = assigns) do
    ~H"""
    <div :if={!@element.is_aside || @show_asides} class="ml-1 sm:ml-4 mb-2 text-justify">
      <.inline_content
        text={@element.content}
        notes={@element.notes}
        show_stage={@show_stage_directions}
      />
    </div>
    """
  end

  defp render_element(assigns) do
    ~H"""
    <div :if={@element.content}>
      <.inline_content
        text={@element.content}
        notes={@element.notes}
        show_stage={@show_stage_directions}
      />
    </div>
    """
  end

  attr :text, :string, default: nil
  attr :notes, :list, default: []
  attr :show_stage, :boolean, default: true

  # One line, kept from the formatter by phx-no-format and built as iodata: a line break
  # between a word and its note's number would show as a space.
  defp inline_content(assigns) do
    html =
      assigns.text
      |> InlineMarkup.parts(assigns.notes)
      |> Enum.map(&part_html(&1, assigns.show_stage))

    assigns = assign(assigns, :html, html)

    ~H"""
    <span phx-no-format>{Phoenix.HTML.raw(@html)}</span>
    """
  end

  # A piece of an inline stage direction, a note's number among them: in a span, and left
  # out while the stage directions are hidden.
  defp part_html(%{stage: %{}}, false), do: ""

  defp part_html(%{stage: %{}} = part, true),
    do: [~s(<span class="inline-stage">), part_html(%{part | stage: nil}, true), "</span>"]

  # Its id is where the Notes view takes the reader back to.
  defp part_html(%{note: note}, _show_stage) do
    [
      ~s(<button type="button" id="nref-),
      escape(note.id),
      ~s(" class="nref" popovertarget="note-),
      escape(note.id),
      ~s(" aria-label="),
      escape(note_label(note)),
      ~s(">),
      Integer.to_string(note.number),
      "</button>"
    ]
  end

  defp part_html(%{italic: true, text: text}, _show_stage), do: ["<em>", escape(text), "</em>"]
  defp part_html(%{text: text}, _show_stage), do: escape(text)

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  defp note_label(note), do: "#{PlayLabels.note_type_label(note.type)} #{note.number}"

  @doc """
  The play's notes in reading order, each with what it hangs on (`anchor`), the word it
  glosses and where it is: the division's and the scene's titles, and the line's number
  when it has one. The public Notes view and the admin's Notes tab both list these.
  """
  def note_entries(divisions) do
    for %{note: note, anchor: anchor, division: division, scene: scene} <-
          Note.with_anchors(divisions) do
      line = if match?(%Division{}, anchor), do: nil, else: anchor.line_number

      where =
        [
          division.title || String.capitalize(division.type),
          scene && scene.title,
          line && gettext("line %{n}", n: line)
        ]
        |> Enum.reject(&is_nil/1)
        |> Enum.join(", ")

      %{
        note: note,
        anchor: anchor,
        glossed: Note.glossed(note, PlayContent.anchor_text(anchor)),
        where: where
      }
    end
  end

  attr :notes, :list, required: true, doc: "`%{note, glossed, where}`, in reading order"
  attr :type, :string, default: nil, doc: "the one type shown, or nil for all"

  @doc """
  The play's notes as a list: each one's type, the word it glosses, where it is (a button
  back to its number in the text) and its paragraphs. Buttons filter by type when the play
  uses two or more.
  """
  def notes_list(assigns) do
    types = assigns.notes |> Enum.map(&note_key(&1.note)) |> Enum.uniq()
    shown = Enum.filter(assigns.notes, &(assigns.type in [nil, note_key(&1.note)]))
    assigns = assign(assigns, types: types, shown: shown)

    ~H"""
    <div
      :if={length(@types) > 1}
      role="group"
      aria-label={gettext("Note type")}
      class="flex flex-wrap gap-2 mb-6"
    >
      <button
        :for={{key, label} <- [{"", gettext("All")} | Enum.map(@types, &{&1, type_label(&1)})]}
        type="button"
        phx-click="filter_notes"
        phx-value-type={key}
        aria-pressed={to_string((@type || "") == key)}
        class={["btn btn-xs", if((@type || "") == key, do: "btn-primary", else: "btn-ghost")]}
      >
        {label}
      </button>
    </div>
    <ol class="space-y-5 list-decimal pl-6 text-sm">
      <li :for={entry <- @shown} id={"play-note-#{entry.note.id}"} value={entry.note.number}>
        <p class="flex flex-wrap items-baseline gap-x-2 text-base-content/60">
          <b class="text-base-content">{PlayLabels.note_type_label(entry.note.type)}</b>
          <i :if={entry.glossed} class="text-base-content font-serif">{entry.glossed}</i>
          <button
            type="button"
            phx-click="show_note"
            phx-value-id={entry.note.id}
            class="link link-hover text-primary"
          >
            {entry.where}
          </button>
        </p>
        <p :for={paragraph <- Note.paragraphs(entry.note)} class="mt-1">
          <.inline_content text={paragraph} />
        </p>
      </li>
    </ol>
    """
  end

  defp note_key(note), do: PlayLabels.note_type_key(note.type)
  defp type_label("other"), do: PlayLabels.note_type_label(nil)
  defp type_label(type), do: PlayLabels.note_type_label(type)

  attr :notes, :list, required: true

  # The play's notes, each a popover its number opens.
  defp endnotes(assigns) do
    ~H"""
    <section
      :if={@notes != []}
      class="play-notes"
      role="doc-endnotes"
      aria-label={gettext("Notes")}
    >
      <ol>
        <li :for={note <- @notes} id={"note-#{note.id}"} popover value={note.number}>
          <button
            type="button"
            popovertarget={"note-#{note.id}"}
            popovertargetaction="hide"
            aria-label={gettext("Close")}
            class="float-right"
          >
            ×
          </button>
          <b>{PlayLabels.note_type_label(note.type)}</b>
          <i :if={note.term}><.inline_content text={note.term} /></i>
          <p :for={paragraph <- Note.paragraphs(note)}><.inline_content text={paragraph} /></p>
        </li>
      </ol>
    </section>
    """
  end
end
