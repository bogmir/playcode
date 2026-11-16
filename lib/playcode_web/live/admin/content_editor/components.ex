defmodule PlaycodeWeb.Admin.ContentEditor.Components do
  @moduledoc """
  The pieces more than one tab of the content editor (`PlaycodeWeb.Admin.PlayContentEditorLive`)
  draws: the sortable list and its handle, and the labels of a division and of a form's title.
  """

  use PlaycodeWeb, :html

  attr :id, :string, required: true
  attr :rest, :global, doc: "`data-event`, the event a drop pushes, and `data-parent`"
  slot :inner_block, required: true

  # A list whose rows (`.drag-item`, each with a `drag_handle/1`) are reordered by dragging.
  def drag_sort_list(assigns) do
    ~H"""
    <div id={@id} phx-hook=".DragSortList" {@rest}>
      {render_slot(@inner_block)}
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".DragSortList">
      export default {
        mounted() {
          this.dragEl = null
          this.placeholder = null
          this.eventName = this.el.dataset.event

          // One listener on the list, not one per handle: the patch after a drop can
          // leave a handle in another row, so the row is found when the drag starts.
          // A nested list's rows belong to its own hook.
          const start = (e, clientY) => {
            const item = e.target.closest(".drag-handle")?.closest(".drag-item")
            if (item?.parentElement !== this.el) return
            e.preventDefault()
            this.startDrag(item, clientY)
          }
          this.el.addEventListener("mousedown", (e) => start(e, e.clientY))
          this.el.addEventListener("touchstart", (e) => start(e, e.touches[0].clientY), { passive: false })
        },

        startDrag(item, startY) {
          this.dragEl = item
          const rect = item.getBoundingClientRect()
          const containerRect = this.el.getBoundingClientRect()

          // Create placeholder
          this.placeholder = document.createElement("div")
          this.placeholder.className = "border-2 border-dashed border-primary/30 rounded bg-primary/5 transition-all"
          this.placeholder.style.height = rect.height + "px"
          item.parentNode.insertBefore(this.placeholder, item)

          // Style dragged element
          item.style.position = "fixed"
          item.style.zIndex = "50"
          item.style.width = rect.width + "px"
          item.style.left = rect.left + "px"
          item.style.top = rect.top + "px"
          item.style.boxShadow = "0 8px 25px -5px rgba(0,0,0,0.15), 0 4px 10px -6px rgba(0,0,0,0.1)"
          item.style.opacity = "0.95"
          item.style.borderRadius = "0.5rem"
          item.style.background = "var(--color-base-100)"
          item.style.transition = "box-shadow 0.2s, opacity 0.2s"
          item.classList.add("ring-2", "ring-primary/30")

          this.offsetY = startY - rect.top

          this.moveHandler = (e) => {
            const clientY = e.touches ? e.touches[0].clientY : e.clientY
            this.onDragMove(clientY)
          }
          this.upHandler = () => this.endDrag()

          document.addEventListener("mousemove", this.moveHandler)
          document.addEventListener("mouseup", this.upHandler)
          document.addEventListener("touchmove", this.moveHandler, { passive: false })
          document.addEventListener("touchend", this.upHandler)
        },

        onDragMove(clientY) {
          if (!this.dragEl) return
          this.dragEl.style.top = (clientY - this.offsetY) + "px"

          // find the item we're hovering over
          const items = [...this.el.querySelectorAll(":scope > .drag-item")].filter(el => el !== this.dragEl)
          let after = null
          for (const item of items) {
            const box = item.getBoundingClientRect()
            const midY = box.top + box.height / 2
            if (clientY < midY) { after = item; break }
          }

          if (after) {
            this.el.insertBefore(this.placeholder, after)
          } else {
            this.el.appendChild(this.placeholder)
          }
        },

        endDrag() {
          if (!this.dragEl) return

          document.removeEventListener("mousemove", this.moveHandler)
          document.removeEventListener("mouseup", this.upHandler)
          document.removeEventListener("touchmove", this.moveHandler)
          document.removeEventListener("touchend", this.upHandler)

          // Insert the real element where the placeholder is
          this.el.insertBefore(this.dragEl, this.placeholder)
          this.placeholder.remove()

          // Reset styles
          this.dragEl.style.position = ""
          this.dragEl.style.zIndex = ""
          this.dragEl.style.width = ""
          this.dragEl.style.left = ""
          this.dragEl.style.top = ""
          this.dragEl.style.boxShadow = ""
          this.dragEl.style.opacity = ""
          this.dragEl.style.borderRadius = ""
          this.dragEl.style.background = ""
          this.dragEl.style.transition = ""
          this.dragEl.classList.remove("ring-2", "ring-primary/30")

          // Update position numbers
          this.el.querySelectorAll(":scope > .drag-item").forEach((item, i) => {
            const posEl = item.querySelector(".drag-position")
            if (posEl) posEl.textContent = i + 1
          })

          // Collect new order and push to server
          // Only this list's own rows: an act's nested list is a hook of its own.
          const ids = [...this.el.querySelectorAll(":scope > .drag-item")].map(el => el.dataset.id)
          this.pushEvent(this.eventName, { ids, parent: this.el.dataset.parent })

          // Brief highlight animation
          this.dragEl.style.transition = "background-color 0.3s"
          this.dragEl.style.backgroundColor = "oklch(from var(--color-primary) l c h / 0.08)"
          setTimeout(() => {
            if (this.dragEl) this.dragEl.style.backgroundColor = ""
          }, 400)

          this.dragEl = null
        }
      }
    </script>
    """
  end

  def drag_handle(assigns) do
    ~H"""
    <button
      type="button"
      class="drag-handle shrink-0 cursor-grab active:cursor-grabbing p-1 rounded text-base-content/70 hover:text-base-content hover:bg-base-200/60"
      aria-label={gettext("Drag to reorder")}
    >
      <.icon name="hero-bars-3-mini" class="size-4" />
    </button>
    """
  end

  def division_label(div) do
    if div.title do
      div.title
    else
      if div.number,
        do: "#{String.capitalize(div.type)} #{div.number}",
        else: String.capitalize(div.type)
    end
  end

  def editing_label(nil), do: gettext("Add")
  def editing_label(_), do: gettext("Edit")
end
