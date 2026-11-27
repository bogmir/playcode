// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/playcode"
import topbar from "../vendor/topbar"
import {syncPanels} from "./sync_scroll.mjs"
import {lineAt, rangeOf, nearestMarked, lineAtHeight} from "./premarked.mjs"
// The published site's script: its EMOTHE.stepper runs the play page's arrows too.
import "../../priv/static_site/site.js"

// PremarkedText hook: the premarked page's text box. The text is kept in the browser per
// play until imported; the caret shows its line in the preview, a click on a line of the
// preview or on a warning selects that line in the text box, and scrolling either pane
// brings the other to the same line.
const PremarkedText = {
  mounted() {
    this.key = `playcode.premarked.${this.el.dataset.play}`
    this.preview = document.getElementById("premarked-preview")
    const kept = this.stored(() => localStorage.getItem(this.key))
    if (kept && !this.el.value.trim()) {
      this.el.value = kept
      this.el.dispatchEvent(new Event("input", {bubbles: true}))
    }
    this.el.addEventListener("input", () => { this.keep(); this.lineTops = null })
    const follow = () => this.show(lineAt(this.el.value, this.el.selectionStart))
    this.el.addEventListener("click", follow)
    this.el.addEventListener("keyup", follow)
    this.onClick = (event) => {
      const target = event.target.closest("#premarked-preview [data-line], #premarked-warnings [data-line], #premarked-errors [data-line]")
      if (target) this.select(Number(target.dataset.line))
    }
    document.addEventListener("click", this.onClick)
    // Only the pane scrolled by hand leads: the other one's scroll events are its echo.
    for (const pane of [this.el, this.preview]) {
      for (const type of ["wheel", "pointerdown", "touchstart", "keydown"]) {
        pane.addEventListener(type, () => { this.leader = pane }, {passive: true})
      }
    }
    this.el.addEventListener("scroll", () => {
      if (this.leader === this.el) this.frame(() => this.previewTo(lineAtHeight(this.tops(), this.el.scrollTop)))
    })
    this.preview.addEventListener("scroll", () => {
      if (this.leader === this.preview) this.frame(() => { this.el.scrollTop = this.tops()[this.previewLine()] ?? 0 })
    })
    this.onResize = () => { this.lineTops = null }
    window.addEventListener("resize", this.onResize)
    this.handleEvent("premarked:fill", ({text}) => { this.el.value = text; this.lineTops = null; this.keep() })
    this.handleEvent("premarked:clear", () => this.stored(() => localStorage.removeItem(this.key)))
  },
  destroyed() {
    document.removeEventListener("click", this.onClick)
    window.removeEventListener("resize", this.onResize)
    this.mirror?.remove()
  },
  keep() { this.stored(() => localStorage.setItem(this.key, this.el.value)) },
  // A private window or blocked storage leaves the page working, without it.
  stored(use) { try { return use() } catch (_error) { return null } },
  frame(step) {
    cancelAnimationFrame(this.pending)
    this.pending = requestAnimationFrame(step)
  },
  // Where each line of the text starts in the box, wrapped as the box wraps it: measured on
  // a hidden copy, again after an edit or a resize.
  tops() {
    if (this.lineTops) return this.lineTops
    const style = getComputedStyle(this.el)
    this.mirror ??= document.body.appendChild(document.createElement("div"))
    Object.assign(this.mirror.style, {
      position: "absolute", visibility: "hidden", top: "0", left: "-9999px", boxSizing: "border-box",
      width: `${this.el.clientWidth}px`, padding: style.padding, font: style.font,
      letterSpacing: style.letterSpacing, whiteSpace: "pre-wrap", overflowWrap: "break-word",
    })
    this.mirror.replaceChildren(...this.el.value.split("\n").map((line) => {
      const row = document.createElement("div")
      row.textContent = line || "\u200b"
      return row
    }))
    this.lineTops = [...this.mirror.children].map((row) => row.offsetTop)
    return this.lineTops
  },
  rowFor(line) {
    const marked = [...this.preview.querySelectorAll("[data-line]")]
    const nearest = nearestMarked(marked.map((el) => Number(el.dataset.line)), line)
    return marked.find((el) => Number(el.dataset.line) === nearest)
  },
  previewLine() {
    const top = this.preview.getBoundingClientRect().top
    const row = [...this.preview.querySelectorAll("[data-line]")].find((el) => el.getBoundingClientRect().bottom > top)
    return row ? Number(row.dataset.line) : 0
  },
  previewTo(line, from = 0) {
    const target = this.rowFor(line)
    if (target) this.preview.scrollTop += target.getBoundingClientRect().top - this.preview.getBoundingClientRect().top - from
    return target
  },
  show(line) {
    this.preview.querySelectorAll(".premarked-current").forEach((el) => el.classList.remove("premarked-current"))
    this.previewTo(line, this.preview.clientHeight / 3)?.classList.add("premarked-current")
  },
  select(line) {
    this.leader = null
    const [start, end] = rangeOf(this.el.value, line)
    this.el.focus()
    this.el.setSelectionRange(start, end)
    this.el.scrollTop = Math.max(0, (this.tops()[line] ?? 0) - this.el.clientHeight / 3)
    this.show(line)
  },
}

// Stepper hook: the arrows that step through the shared lines or the stage directions.
// Its element carries the switches that re-render the text (data-switches), so turning
// one calls updated(): a re-count, and the outline LiveView's patch dropped goes back on.
const Stepper = {
  mounted() { this.stepper = window.EMOTHE.stepper(this.el, this.el.dataset.selector) },
  updated() { this.stepper.refresh() },
}

// AlignParts hook: a shared line's later parts lined up where they fit (EMOTHE.align). The
// patch drops data-aligned; the element's data-switches change with it, so updated() runs.
const AlignParts = {
  mounted() { window.EMOTHE.align(this.el) },
  updated() { window.EMOTHE.align(this.el) },
}

// ScrollSpy hook: highlights the sidebar link matching the currently visible section
const ScrollSpy = {
  mounted() { this._setup() },
  updated() { this._setup() },
  destroyed() { if (this._obs) this._obs.disconnect() },
  _setup() {
    if (this._obs) this._obs.disconnect()

    const links = this.el.querySelectorAll("a[href^='#']")
    const ids = Array.from(links).map(a => a.getAttribute("href").slice(1))
    const targets = ids.map(id => document.getElementById(id)).filter(Boolean)
    if (!targets.length) return

    // Track which sections are currently intersecting
    const visible = new Map()

    this._obs = new IntersectionObserver((entries) => {
      for (const e of entries) {
        if (e.isIntersecting) {
          visible.set(e.target.id, e.boundingClientRect.top)
        } else {
          visible.delete(e.target.id)
        }
      }

      // Prefer the section nearest the top reading line.
      // This avoids parent sections (e.g., acts) staying active while
      // their nested scenes are currently in view.
      const readingLine = 96
      let activeId = null
      let bestPastTop = -Infinity
      let bestFutureTop = Infinity

      for (const [id, top] of visible) {
        if (top <= readingLine && top > bestPastTop) {
          bestPastTop = top
          activeId = id
        }

        if (top > readingLine && top < bestFutureTop) {
          bestFutureTop = top
        }
      }

      if (!activeId && Number.isFinite(bestFutureTop)) {
        for (const [id, top] of visible) {
          if (top === bestFutureTop) {
            activeId = id
            break
          }
        }
      }

      links.forEach(link => {
        const isActive = link.getAttribute("href").slice(1) === activeId
        link.classList.toggle("scroll-spy-active", isActive)
      })
    }, { rootMargin: "-5% 0px -65% 0px", threshold: 0 })

    targets.forEach(t => this._obs.observe(t))
  }
}

// SyncScroll hook: keeps the comparison panels at the same place (sync_scroll.mjs).
// A LiveView patch can replace the panels, so updated() starts over.
const SyncScroll = {
  mounted() { this.stop = syncPanels(this.el) },
  updated() { this.stop(); this.stop = syncPanels(this.el) },
  destroyed() { this.stop() },
}

// ShiftClick hook: captures shiftKey on click and pushes el_toggle_element with shift flag
const ShiftClick = {
  mounted() {
    this.el.addEventListener("click", (e) => {
      e.preventDefault()
      if (e.shiftKey) window.getSelection()?.removeAllRanges()
      this.pushEvent("el_toggle_element", {
        id: this.el.dataset.id,
        shift: e.shiftKey
      })
    })
  }
}

// AutoDismiss hook: clears an info flash after a short delay, like clicking it.
// updated() restarts the timer so a replacement message gets its full time.
const AutoDismiss = {
  mounted() { this.arm() },
  updated() { this.arm() },
  destroyed() { clearTimeout(this.timer) },
  arm() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.pushEvent("lv:clear-flash", {key: this.el.dataset.kind}), 2500)
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ScrollSpy, SyncScroll, ShiftClick, AutoDismiss, Stepper, AlignParts, PremarkedText},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// The Notes view's way back to the text: the server switches to it, then names the
// note's number to scroll to (PlaycodeWeb.PlayShowLive, "show_note").
window.addEventListener("phx:scroll-to", ({detail}) => {
  const target = document.getElementById(detail.id)
  if (!target) return
  target.scrollIntoView({block: "center"})
  target.focus({preventScroll: true})
})

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

