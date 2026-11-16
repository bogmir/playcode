defmodule PlaycodeWeb.Admin.ContentEditor.Preview do
  @moduledoc """
  The content editor's Preview tab: the play's text as its pages print it.
  """

  use PlaycodeWeb, :html

  import PlaycodeWeb.Components.PlayText

  attr :preview_divisions, :list, required: true

  def tab(assigns) do
    ~H"""
    <div class="animate-in fade-in">
      <div class="mb-4">
        <h2 class="text-lg font-semibold text-base-content">{gettext("Play Text Preview")}</h2>
      </div>
      <div
        id="preview-scroll-container"
        phx-hook=".PreviewScroll"
        class="rounded-box border border-base-300 bg-base-100 p-6 shadow-sm max-h-[70vh] overflow-y-auto"
        tabindex="0"
        role="region"
        aria-label={gettext("Play Text Preview")}
      >
        <script :type={Phoenix.LiveView.ColocatedHook} name=".PreviewScroll">
          export default {
            mounted() {
              this.handleEvent("scroll-to-preview", ({target}) => {
                // Wait for LiveView DOM patch to complete
                setTimeout(() => {
                  const el = document.getElementById(target)
                  if (el) {
                    const container = this.el
                    const elTop = el.offsetTop - container.offsetTop
                    container.scrollTo({top: elTop, behavior: "smooth"})
                  }
                }, 100)
              })
            }
          }
        </script>
        <div :if={@preview_divisions == []} class="text-center py-8 text-base-content/70">
          <.icon name="hero-document" class="mx-auto mb-2 size-8 text-base-content/70" />
          <p>{gettext("No content to preview yet.")}</p>
        </div>
        <.play_body
          :if={@preview_divisions != []}
          divisions={@preview_divisions}
          show_line_numbers={true}
          show_stage_directions={true}
          show_folio={true}
        />
      </div>
    </div>
    """
  end
end
