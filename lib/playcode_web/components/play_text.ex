defmodule PlaycodeWeb.Components.PlayText do
  @moduledoc """
  Components for rendering play text: speeches, verse lines, stage directions.
  Styled to match the production EMOTHE/Artelope color scheme and fonts.
  """
  use Phoenix.Component
  use Gettext, backend: PlaycodeWeb.Gettext

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
        <.inline_content text={@element.content} notes={@element.notes} />
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
      <.inline_content text={@element.content} notes={@element.notes} />
    </div>
    """
  end

  defp render_element(assigns) do
    ~H"""
    <div :if={@element.content}>
      <.inline_content text={@element.content} notes={@element.notes} />
    </div>
    """
  end

  attr :text, :string, default: nil
  attr :notes, :list, default: []

  # One line, kept from the formatter by phx-no-format: a line break between a word and
  # its note's number would show as a space.
  defp inline_content(assigns) do
    assigns = assign(assigns, :parts, InlineMarkup.parts(assigns.text, assigns.notes))

    ~H"""
    <span phx-no-format><%= for part <- @parts do %><%= case part do %><% %{note: note} -> %><button type="button" class="nref" popovertarget={"note-#{note.id}"} aria-label={note_label(note)}>{note.number}</button><% %{italic: true} -> %><em>{part.text}</em><% _ -> %>{part.text}<% end %><% end %></span>
    """
  end

  defp note_label(note), do: "#{PlayLabels.note_type_label(note.type)} #{note.number}"

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
