/* EMOTHE static edition: progressive enhancement only. Every page reads fine without it. */
(function (root) {
  'use strict';
  var E = root.EMOTHE = root.EMOTHE || {};

  // Must agree with Playcode.Export.StaticSite.Search.normalise/1 and words/1:
  // test/fixtures/search_normalisation.json runs against both. U+E000 (private use)
  // holds the ñ's place while the other accents are stripped.
  E.normalise = function (s) {
    return String(s || '').normalize('NFC').toLowerCase().replace(/ñ/g, '\uE000')
      .normalize('NFD').replace(/\p{Mn}/gu, '').replace(/\uE000/g, 'ñ');
  };
  E.words = function (s) { return E.normalise(s).match(/[\p{L}\p{N}]+/gu) || []; };

  // The arrows' choice: of the targets' positions in reading order (each one's middle,
  // from the top of the window), the first below the reading line for 1, the last above
  // it for -1; -1 when there is none. The one on the line is the current one.
  E.step = function (positions, line, dir) {
    if (dir > 0) {
      for (var i = 0; i < positions.length; i++) if (positions[i] > line + 1) return i;
    } else {
      for (var j = positions.length - 1; j >= 0; j--) if (positions[j] < line - 1) return j;
    }
    return -1;
  };

  if (!root.document) return;

  // Arrows in `box` ([data-step="1"] and [data-step="-1"]) that step through what
  // `selector` finds, skipping what is hidden, from where the reader has scrolled to:
  // the one they land on is centred, marked data-current, and counted in [data-step-count].
  E.stepper = function (box, selector) {
    var count = box.querySelector('[data-step-count]');
    var current = null;

    function targets() {
      return Array.prototype.filter.call(document.querySelectorAll(selector), function (el) {
        return el.getClientRects().length > 0;
      });
    }

    function refresh() {
      var all = targets();
      var at = all.indexOf(current) + 1;
      count.textContent = (at || '–') + ' ' + (box.dataset.of || 'of') + ' ' + all.length;
    }

    box.addEventListener('click', function (event) {
      var button = event.target.closest('[data-step]');
      if (!button) return;
      var all = targets();
      var middles = all.map(function (el) { var r = el.getBoundingClientRect(); return (r.top + r.bottom) / 2; });
      // The first press goes from the top of the window, not from its middle: a reader at
      // the start of the play lands on the first one, not the one after.
      var line = current ? root.innerHeight / 2 : 0;
      var i = E.step(middles, line, Number(button.dataset.step));
      if (i < 0) return refresh();
      if (current) current.removeAttribute('data-current');
      current = all[i];
      current.setAttribute('data-current', '');
      current.scrollIntoView({ block: 'center' });
      refresh();
    });

    refresh();
    return { refresh: refresh };
  };

  function initCatalogue() {
    var list = document.querySelector('[data-works]');
    if (!list) return;
    var controls = document.querySelector('[data-catalogue-controls]');
    var facets = document.querySelector('[data-facets]');
    var filter = document.querySelector('[data-filter]');
    var sort = document.querySelector('[data-sort]');
    var count = document.querySelector('[data-count]');
    var works = Array.prototype.slice.call(list.children);
    controls.hidden = false;
    facets.hidden = false;

    function chosen() {
      var out = {};
      facets.querySelectorAll('input:checked').forEach(function (input) { if (input.value) out[input.name] = input.value; });
      return out;
    }

    function matches(entry, query, want) {
      var data = entry.dataset;
      return (!query || data.text.indexOf(query) !== -1) &&
        (!want.lang || data.lang === want.lang) && (!want.form || data.form === want.form) &&
        (!want.kind || data.kind === want.kind) && (!want.coll || data.coll === want.coll);
    }

    function update() {
      var query = E.normalise(filter.value).trim();
      var want = chosen();
      var shown = 0;
      works.forEach(function (work) {
        var visible = Array.prototype.some.call(work.querySelectorAll('[data-play]'), function (entry) {
          return matches(entry, query, want);
        });
        work.hidden = !visible;
        if (visible) shown++;
      });
      count.textContent = shown === works.length ? '' : shown + ' of ' + works.length + ' works';
    }

    function reorder() {
      var key = sort.value;
      works.sort(function (a, b) {
        var x = a.dataset[key] || '', y = b.dataset[key] || '';
        if (x === y) return 0;
        if (key === 'date') { x = x ? Number(x) : Infinity; y = y ? Number(y) : Infinity; return x - y; }
        return x.localeCompare(y);
      });
      works.forEach(function (work) { list.appendChild(work); });
    }

    filter.addEventListener('input', update);
    facets.addEventListener('change', update);
    sort.addEventListener('change', reorder);
  }

  // The Notes page: show one type of note, or all.
  function initNotes() {
    var filter = document.querySelector('[data-note-filter]');
    if (!filter) return;
    var notes = document.querySelectorAll('[data-notes] > li');
    filter.hidden = false;
    filter.addEventListener('change', function (event) {
      var type = event.target.value;
      notes.forEach(function (note) { note.hidden = type !== '' && note.dataset.type !== type; });
    });
  }

  function remembered(key, value) {
    try {
      if (value === undefined) return root.localStorage.getItem('reader.' + key);
      root.localStorage.setItem('reader.' + key, value);
    } catch (e) { return null; }
  }

  function initTools() {
    var tools = document.querySelector('[data-tools]');
    if (!tools) return;
    var body = document.body;
    tools.hidden = false;
    ['ln', 'sd', 'vf', 'va', 'fo', 'rs'].forEach(function (key) { var v = remembered(key); if (v) body.setAttribute('data-' + key, v); });

    var buttons = tools.querySelectorAll('[data-ln-set]');
    buttons.forEach(function (button) {
      button.setAttribute('aria-pressed', String(button.dataset.lnSet === body.dataset.ln));
      button.addEventListener('click', function () {
        body.dataset.ln = button.dataset.lnSet;
        remembered('ln', button.dataset.lnSet);
        buttons.forEach(function (b) { b.setAttribute('aria-pressed', String(b === button)); });
      });
    });

    tools.querySelectorAll('[data-toggle]').forEach(function (box) {
      var key = box.dataset.toggle;
      box.checked = body.getAttribute('data-' + key) !== 'off';
      box.addEventListener('change', function () {
        var value = box.checked ? 'on' : 'off';
        body.setAttribute('data-' + key, value);
        remembered(key, value);
      });
    });

    var select = tools.querySelector('[data-highlight]');
    if (select) {
      var style = document.createElement('style');
      document.head.appendChild(style);
      select.addEventListener('change', function () {
        style.textContent = select.value
          ? '.text .sp:not([data-who~="' + CSS.escape(select.value) + '"]){opacity:.4}' +
            '.text .sp[data-who~="' + CSS.escape(select.value) + '"]{border-left:2px solid var(--accent);padding-left:.5rem;margin-left:calc(-.5rem - 2px)}' : '';
      });
    }
  }

  function copy(text, button) {
    if (!root.navigator.clipboard) return;
    root.navigator.clipboard.writeText(text).then(function () {
      var label = button.textContent;
      button.textContent = 'Copied';
      setTimeout(function () { button.textContent = label; }, 1500);
    }, function () {});
  }

  function initLinks() {
    var text = document.querySelector('[data-cite]');
    if (text) {
      text.addEventListener('click', function (event) {
        var number = event.target.closest('a[href^="#l"]');
        if (!number) return;
        var url = root.location.href.split('#')[0] + number.getAttribute('href');
        copy(text.dataset.cite + ', v. ' + number.textContent.trim() + '. ' + url, number);
      });
    }
    var button = document.querySelector('[data-copy-citation]');
    var citation = document.querySelector('[data-citation]');
    if (button && citation) {
      button.hidden = false;
      button.addEventListener('click', function () {
        copy(citation.textContent.trim() + ' ' + root.location.href.split('#')[0], button);
      });
    }
  }

  document.addEventListener('DOMContentLoaded', function () {
    // The rail is open in the markup so it shows without JS; on a narrow screen it
    // starts closed once JS is here to open it.
    if (root.matchMedia && root.matchMedia('(max-width: 959px)').matches) {
      document.querySelectorAll('details.rail').forEach(function (d) { d.open = false; });
    }
    initCatalogue();
    initNotes();
    initTools();
    initLinks();
  });
})(typeof window !== 'undefined' ? window : globalThis);
