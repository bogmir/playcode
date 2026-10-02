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

  if (!root.document) return;

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

  document.addEventListener('DOMContentLoaded', function () {
    // The rail is open in the markup so it shows without JS; on a narrow screen it
    // starts closed once JS is here to open it.
    if (root.matchMedia && root.matchMedia('(max-width: 959px)').matches) {
      document.querySelectorAll('details.rail').forEach(function (d) { d.open = false; });
    }
    initCatalogue();
  });
})(typeof window !== 'undefined' ? window : globalThis);
