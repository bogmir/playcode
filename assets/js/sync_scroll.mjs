// Scroll sync for the side-by-side comparison: the live page's SyncScroll hook imports
// this module, and the downloadable comparison (Playcode.Export.CompareHtml) inlines it
// with the `export` keywords removed, so both pages behave the same.
//
// Every speech carries data-sync-act, the key of the act it belongs to, and every
// heading data-sync-div (see Division.sync_keys/1). Speeches are paired by proportion,
// not by count: translators merge and split speeches, so speech 40 of one edition's
// act is rarely speech 40 of the other's, but it is about as far through the act.

// The index, among `m` speeches, as far through them as speech `i` of `n`.
export function counterpart(i, n, m) {
  if (m === 0) return null
  if (n <= 1) return 0
  return Math.round((i * (m - 1)) / (n - 1))
}

// `sourceActs` and `targetActs` list each panel's speeches by act key, in reading order.
// Source speech `s` pairs with the speech as far through the same act in the target, or,
// when the target has no such act (an edition kept as one division), as far through the
// whole play. Returns an index into `targetActs`, or null for an empty target.
export function matchSpeech(sourceActs, targetActs, s) {
  const act = sourceActs[s]
  const inAct = (acts) => acts.flatMap((a, k) => (a === act ? [k] : []))
  const from = inAct(sourceActs)
  const to = inAct(targetActs)

  if (to.length > 0) return to[counterpart(from.indexOf(s), from.length, to.length)]
  return counterpart(s, sourceActs.length, targetActs.length)
}

// Keeps the [data-panel] elements inside `container` at the same place in the play. The
// panel under the pointer leads, so the panels it moves do not move it back. Returns a
// function that removes the listeners.
export function syncPanels(container) {
  const panels = Array.from(container.querySelectorAll("[data-panel]"))
  if (panels.length < 2) return () => {}

  const offset = (el, panel) => el.getBoundingClientRect().top - panel.getBoundingClientRect().top

  // The speech or heading nearest the top of the panel, allowing one just scrolled past.
  const topAnchor = (panel) => {
    let best = null
    let bestTop = Infinity
    for (const el of panel.querySelectorAll("[data-sync-act], [data-sync-div]")) {
      const top = offset(el, panel)
      if (top >= -50 && top < bestTop) {
        bestTop = top
        best = el
      }
    }
    return best
  }

  const counterpartIn = (target, anchor, source) => {
    if (anchor.hasAttribute("data-sync-div")) {
      return target.querySelector(`[data-sync-div="${anchor.dataset.syncDiv}"]`)
    }
    const from = Array.from(source.querySelectorAll("[data-sync-act]"))
    const to = Array.from(target.querySelectorAll("[data-sync-act]"))
    const j = matchSpeech(from.map((el) => el.dataset.syncAct), to.map((el) => el.dataset.syncAct), from.indexOf(anchor))
    return j === null ? null : to[j]
  }

  const align = (source, target) => {
    const anchor = topAnchor(source)
    const match = anchor && counterpartIn(target, anchor, source)
    if (match) target.scrollTop += offset(match, target) - offset(anchor, source)
  }

  let leader = null
  let frame = null

  const listeners = panels.map((panel, i) => {
    const enter = () => { leader = i }
    const leave = () => { if (leader === i) leader = null }
    const scroll = () => {
      if (leader !== i || frame) return
      frame = requestAnimationFrame(() => {
        frame = null
        panels.forEach((other, j) => { if (j !== i) align(panel, other) })
      })
    }
    panel.addEventListener("pointerenter", enter)
    panel.addEventListener("pointerleave", leave)
    panel.addEventListener("scroll", scroll, { passive: true })
    return { panel, enter, leave, scroll }
  })

  requestAnimationFrame(() => panels.slice(1).forEach((other) => align(panels[0], other)))

  return () => {
    if (frame) cancelAnimationFrame(frame)
    listeners.forEach(({ panel, enter, leave, scroll }) => {
      panel.removeEventListener("pointerenter", enter)
      panel.removeEventListener("pointerleave", leave)
      panel.removeEventListener("scroll", scroll)
    })
  }
}
