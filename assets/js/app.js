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
  hooks: {...colocatedHooks, ScrollSpy, SyncScroll, ShiftClick, AutoDismiss},
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

