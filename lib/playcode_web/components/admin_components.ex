defmodule PlaycodeWeb.AdminComponents do
  @moduledoc """
  The admin's parts, drawn after the mockup the owner approved on 2026-11-12
  (`docs/superpowers/specs/2026-11-12-admin-design-mock.html`): a page at one of two widths
  and its heading, a card, a label and value list, a count tile, and a play's state band.
  The download group is in `PlaycodeWeb.CoreComponents`, the public catalogue's too.
  """
  use Phoenix.Component
  use Gettext, backend: PlaycodeWeb.Gettext

  @doc """
  An admin page: `:list` for lists and overviews, `:form` for a form, so the content keeps
  its width from one tab to the next.
  """
  attr :width, :atom, values: [:list, :form], default: :list
  slot :inner_block, required: true

  def page(assigns) do
    ~H"""
    <div class={["mx-auto px-4 py-8", if(@width == :form, do: "max-w-4xl", else: "max-w-7xl")]}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc "A page's heading: the `h1`, what the page is for, and its actions."
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def page_header(assigns) do
    ~H"""
    <header class="mb-6 flex flex-wrap items-start justify-between gap-4">
      <div class="min-w-0">
        <h1 class="font-serif text-3xl font-semibold leading-tight text-base-content">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="mt-1 max-w-2xl text-sm text-base-content/70">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div :if={@actions != []} class="flex flex-wrap items-center gap-2">
        {render_slot(@actions)}
      </div>
    </header>
    """
  end

  @doc """
  A card: a titled section with an optional action at the right of its title. `dashed`
  marks one whose action replaces something.
  """
  attr :title, :string, required: true
  attr :count, :integer, default: nil
  attr :id, :string, default: nil
  attr :dashed, :boolean, default: false
  slot :action
  slot :inner_block, required: true

  def card(assigns) do
    ~H"""
    <section
      id={@id}
      class={[
        "mb-5 rounded-box border border-base-300 bg-base-100 px-4 py-4",
        @dashed && "border-dashed"
      ]}
    >
      <header class="mb-2.5 flex items-baseline justify-between gap-4">
        <h2 class="text-base font-semibold text-base-content">
          {@title}
          <span :if={@count} class="ml-1 font-normal tabular-nums text-base-content/70">
            {@count}
          </span>
        </h2>
        <div :if={@action != []} class="text-sm">{render_slot(@action)}</div>
      </header>
      {render_slot(@inner_block)}
    </section>
    """
  end

  @doc "Labels and values, aligned in two columns. An item left out with `:if` leaves no row."
  attr :class, :string, default: nil

  slot :item, required: true do
    attr :label, :string, required: true
  end

  def field_list(assigns) do
    ~H"""
    <dl class={["grid grid-cols-[minmax(0,9.5rem)_minmax(0,1fr)] gap-x-4 gap-y-1.5", @class]}>
      <%= for item <- @item do %>
        <dt class="pt-0.5 text-sm text-base-content/70">{item.label}</dt>
        <dd class="min-w-0 break-words">{render_slot(item)}</dd>
      <% end %>
    </dl>
    """
  end

  @doc "A count that links to its section; none reads as an invitation to add one."
  attr :count, :integer, required: true
  attr :label, :string, required: true
  attr :navigate, :string, required: true

  def count_tile(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class="block rounded-box border border-base-300 bg-base-100 px-3.5 py-2.5 hover:border-primary"
    >
      <span class={[
        "block text-2xl font-semibold tabular-nums",
        @count == 0 && "text-base-content/70"
      ]}>
        {@count}
      </span>
      <span class="text-sm text-base-content/70">
        {@label}<span :if={@count == 0} class="font-semibold text-primary"> · {gettext("add")}</span>
      </span>
    </.link>
    """
  end

  @doc """
  Who sees the play, here and on the published site, with the one button that changes it.
  It sends `set_status` with the status the button gives. `deployed` is the
  `content_version` the last deploy published the play with, nil when it did not.
  """
  attr :play, :map, required: true
  attr :deployed, :integer, default: nil

  def state_band(assigns) do
    ~H"""
    <div
      id="play-state"
      class={[
        "my-5 flex flex-wrap items-center justify-between gap-3 rounded-box border px-4 py-3",
        if(@play.is_complete,
          do: "border-success/40 bg-success/10",
          else: "border-warning/40 bg-warning/10"
        )
      ]}
    >
      <p>
        <span class={[
          "badge badge-sm mr-2 font-semibold",
          if(@play.is_complete, do: "badge-success", else: "badge-warning")
        ]}>
          {if @play.is_complete, do: gettext("Complete"), else: gettext("Draft")}
        </span>
        {state_sentence(@play, @deployed)}
      </p>
      <button
        :if={!@play.is_complete}
        phx-click="set_status"
        phx-value-status="complete"
        class="btn btn-sm btn-outline btn-primary"
      >
        {gettext("Mark as complete")}
      </button>
      <button
        :if={@play.is_complete}
        phx-click="set_status"
        phx-value-status="draft"
        class="btn btn-sm btn-outline btn-primary"
      >
        {gettext("Back to draft")}
      </button>
    </div>
    """
  end

  defp state_sentence(%{is_complete: true, content_version: version}, version),
    do: gettext("Published on the site.")

  defp state_sentence(%{is_complete: true}, nil),
    do:
      gettext("Everyone sees it here. The next Generate and Deploy put it on the published site.")

  defp state_sentence(%{is_complete: true}, _older),
    do: gettext("Published on the site; changed since the last deploy.")

  defp state_sentence(_draft, nil),
    do: gettext("Only the team sees it. It is not on the published site.")

  defp state_sentence(_draft, _deployed),
    do:
      gettext(
        "Only the team sees it here. The published site keeps it until the next Generate and Deploy."
      )
end
