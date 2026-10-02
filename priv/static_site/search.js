/* EMOTHE static edition: full-text search over the files StaticSite.Search writes.
   Loaded only by search.html, after site.js (EMOTHE.normalise, EMOTHE.words). */
(function (root) {
  'use strict';
  var E = root.EMOTHE = root.EMOTHE || {};
  var S = E.search = E.search || {};
  var store = { plays: null, index: {}, lines: {} };
  var waiting = {};

  // Must match Playcode.Export.StaticSite.Search.lines_per_chunk/0.
  S.LINES_PER_CHUNK = 100;

  S.load = function (kind, key, value) {
    if (kind === 'plays') store.plays = value; else store[kind][key] = value;
    var id = kind + ':' + key, callbacks = waiting[id] || [];
    delete waiting[id];
    callbacks.forEach(function (resolve) { resolve(); });
  };

  S.shardKey = function (word) { return Array.from(word).slice(0, 2).join(''); };

  S.shardFile = function (key) {
    return Array.from(key).map(function (c) {
      return /^[a-z0-9]$/.test(c) ? c : 'u' + c.codePointAt(0).toString(16).padStart(4, '0');
    }).join('');
  };

  S.chunkKey = function (code, line) { return code + '/' + Math.floor(line / S.LINES_PER_CHUNK); };

  // [play, n, d1 … dn, play, n, …], d = (line - previous line) * 2 + flag  →  [[play, line, flag]]
  S.decode = function (list) {
    var out = [];
    for (var i = 0; i < list.length; i += 2 + list[i + 1]) {
      var line = 0;
      for (var j = 0; j < list[i + 1]; j++) {
        var d = list[i + 2 + j];
        line += Math.floor(d / 2);
        out.push([list[i], line, d % 2]);
      }
    }
    return out;
  };

  // Words in quotes are a phrase; every word, in a phrase or not, must occur in the line.
  S.parse = function (query) {
    var phrases = [];
    var rest = String(query || '').replace(/"([^"]*)"/g, function (_, inner) {
      var words = E.words(inner);
      if (words.length) phrases.push(words);
      return ' ';
    });
    var all = E.words(rest);
    phrases.forEach(function (phrase) { all = all.concat(phrase); });
    return { words: all.filter(function (w, i) { return all.indexOf(w) === i; }), phrases: phrases };
  };

  // A one-letter word has a shard of its own, so it can only match whole.
  S.matches = function (token, word, mode) {
    return mode === 'prefix' && Array.from(word).length > 1 ? token.indexOf(word) === 0 : token === word;
  };

  S.hasPhrase = function (tokens, phrase, mode) {
    for (var i = 0; i + phrase.length <= tokens.length; i++) {
      var ok = true;
      for (var j = 0; j < phrase.length && ok; j++) ok = S.matches(tokens[i + j], phrase[j], mode);
      if (ok) return true;
    }
    return false;
  };

  // Hits for one word: {"play:line": 1 for a stage direction, 0 for spoken text}.
  S.hits = function (shard, word, mode) {
    var hits = {};
    Object.keys(shard || {}).forEach(function (token) {
      if (!S.matches(token, word, mode)) return;
      S.decode(shard[token]).forEach(function (h) { hits[h[0] + ':' + h[1]] = h[2]; });
    });
    return hits;
  };

  S.intersect = function (maps) {
    var out = {};
    if (!maps.length) return out;
    Object.keys(maps[0]).forEach(function (k) {
      if (maps.every(function (m) { return k in m; })) out[k] = maps[0][k];
    });
    return out;
  };

  if (!root.document) return;

  var FIRST_PLAYS = 10, FIRST_LINES = 5;
  var form, results, count, facetsEl, state = null, renders = 0, runs = 0;
  var FACETS = [
    ['language', 'Language', function (play) { return play.language_name; }],
    ['author', 'Author', function (play) { return play.author || '—'; }],
    ['kind', 'Kind', function (play) { return play.kind === 'original' ? 'Originals' : 'Translations'; }],
    ['type', 'Text', function (play, stage) { return stage ? 'Stage directions' : 'Spoken'; }]
  ];

  function el(tag, cls, text) {
    var node = document.createElement(tag);
    if (cls) node.className = cls;
    if (text !== undefined && text !== null) node.textContent = text;
    return node;
  }

  function button(label, onClick) {
    var b = el('button', 'more', label);
    b.type = 'button';
    b.addEventListener('click', onClick);
    return b;
  }

  // Loads a search file once; a missing file (a word with no shard) loads as empty.
  function need(kind, key, src) {
    var have = kind === 'plays' ? store.plays : store[kind][key];
    if (have) return Promise.resolve();
    var id = kind + ':' + key;
    return new Promise(function (resolve) {
      if (waiting[id]) { waiting[id].push(resolve); return; }
      waiting[id] = [resolve];
      var script = document.createElement('script');
      script.src = src;
      script.onerror = function () { S.load(kind, key, kind === 'index' ? {} : kind === 'plays' ? [] : { speakers: [], lines: [] }); };
      document.head.appendChild(script);
    });
  }

  // Loads the chunks holding the given [play, line] pairs.
  function loadLines(pairs) {
    var keys = {};
    pairs.forEach(function (pl) { keys[S.chunkKey(store.plays[pl[0]].code, pl[1])] = true; });
    return Promise.all(Object.keys(keys).map(function (key) {
      return need('lines', key, 'search/lines/' + key + '.js');
    }));
  }

  // A line and its chunk, or null when the chunk could not be loaded.
  function lineOf(p, l) {
    var chunk = store.lines[S.chunkKey(store.plays[p].code, l)];
    var row = chunk && chunk.lines[l % S.LINES_PER_CHUNK];
    return row ? { row: row, speakers: chunk.speakers } : null;
  }

  function pairsOf(hits) {
    return Object.keys(hits).map(function (k) { return k.split(':').map(Number); });
  }

  function phraseFilter(hits, phrases, mode) {
    var out = {};
    pairsOf(hits).forEach(function (pl) {
      var line = lineOf(pl[0], pl[1]);
      if (line && phrases.every(function (p) { return S.hasPhrase(E.words(line.row[5]), p, mode); })) {
        out[pl[0] + ':' + pl[1]] = hits[pl[0] + ':' + pl[1]];
      }
    });
    return out;
  }

  function run() {
    var query = form.elements.q.value, mode = form.elements.mode.value;
    var my = ++runs;
    try { root.history.replaceState(null, '', '?' + new URLSearchParams({ q: query, mode: mode }).toString()); } catch (e) { /* file:// may refuse */ }
    var parsed = S.parse(query);
    if (!parsed.words.length) { state = null; render(); return; }
    var keys = parsed.words.map(S.shardKey).filter(function (k, i, a) { return a.indexOf(k) === i; });
    count.textContent = 'Searching…';
    need('plays', 'all', 'search/plays.js')
      .then(function () {
        return Promise.all(keys.map(function (k) { return need('index', k, 'search/index/' + S.shardFile(k) + '.js'); }));
      })
      .then(function () {
        var hits = S.intersect(parsed.words.map(function (w) { return S.hits(store.index[S.shardKey(w)], w, mode); }));
        if (!parsed.phrases.length) return hits;
        // A phrase is checked against the text, so its candidate lines' chunks are loaded.
        return loadLines(pairsOf(hits)).then(function () { return phraseFilter(hits, parsed.phrases, mode); });
      })
      .then(function (hits) {
        if (my !== runs) return;
        state = { hits: hits, words: parsed.words, mode: mode, open: {}, filters: {}, allPlays: false };
        render();
      });
  }

  function passes(play, stage, skip) {
    return FACETS.every(function (f) {
      var want = state.filters[f[0]];
      return f === skip || !want || f[2](play, stage) === want;
    });
  }

  function render() {
    var token = ++renders;
    results.textContent = '';
    facetsEl.textContent = '';
    if (!state) { count.textContent = ''; return; }

    var groups = {};
    Object.keys(state.hits).forEach(function (k) {
      var pl = k.split(':').map(Number);
      if (passes(store.plays[pl[0]], state.hits[k] === 1)) (groups[pl[0]] = groups[pl[0]] || []).push(pl[1]);
    });
    var order = Object.keys(groups).map(Number).sort(function (a, b) {
      return groups[b].length - groups[a].length || store.plays[a].title.localeCompare(store.plays[b].title);
    });
    var total = order.reduce(function (n, p) { return n + groups[p].length; }, 0);
    count.textContent = total + (total === 1 ? ' line' : ' lines') + ' in ' + order.length + (order.length === 1 ? ' play' : ' plays');
    renderFacets();

    var shown = state.allPlays ? order : order.slice(0, FIRST_PLAYS);
    var visible = {}, pairs = [];
    shown.forEach(function (p) {
      var lines = groups[p].sort(function (a, b) { return a - b; });
      visible[p] = state.open[p] ? lines : lines.slice(0, FIRST_LINES);
      visible[p].forEach(function (l) { pairs.push([p, l]); });
    });
    loadLines(pairs).then(function () {
      if (token !== renders) return;
      shown.forEach(function (p) { results.appendChild(group(p, groups[p].length, visible[p])); });
      if (order.length > shown.length) {
        results.appendChild(button('Show all ' + order.length + ' plays', function () { state.allPlays = true; render(); }));
      }
    });
  }

  function renderFacets() {
    FACETS.forEach(function (f) {
      var counts = {};
      Object.keys(state.hits).forEach(function (k) {
        var p = Number(k.split(':')[0]), stage = state.hits[k] === 1, play = store.plays[p];
        if (passes(play, stage, f)) { var v = f[2](play, stage); counts[v] = (counts[v] || 0) + 1; }
      });
      var values = Object.keys(counts).sort(function (a, b) { return counts[b] - counts[a]; });
      if (values.length < 2 && !state.filters[f[0]]) return;
      var fieldset = el('fieldset', 'facet');
      fieldset.appendChild(el('legend', null, f[1]));
      [''].concat(values).forEach(function (v) {
        var label = el('label'), input = el('input');
        input.type = 'radio';
        input.name = 'facet-' + f[0];
        input.value = v;
        input.checked = (state.filters[f[0]] || '') === v;
        input.addEventListener('change', function () { state.filters[f[0]] = v; state.open = {}; render(); });
        label.appendChild(input);
        label.appendChild(el('span', null, v || 'All'));
        label.appendChild(el('span', 'count', v ? String(counts[v]) : ''));
        fieldset.appendChild(label);
      });
      facetsEl.appendChild(fieldset);
    });
  }

  function group(p, total, lines) {
    var play = store.plays[p];
    var section = el('section', 'group'), heading = el('h2'), link = el('a', null, play.title);
    link.href = 'plays/' + play.code + '/index.html';
    heading.appendChild(link);
    section.appendChild(heading);
    var meta = [play.author, play.kind === 'translation' ? 'translation' : null, total + (total === 1 ? ' line' : ' lines')];
    section.appendChild(el('p', 'group-meta', meta.filter(Boolean).join(' · ')));
    var list = el('ol', 'hits');
    lines.forEach(function (l) {
      var line = lineOf(p, l);
      if (line) list.appendChild(hit(play, line));
    });
    section.appendChild(list);
    if (total > lines.length) section.appendChild(button('Show all ' + total, function () { state.open[p] = true; render(); }));
    return section;
  }

  function hit(play, line) {
    var row = line.row, li = el('li', 'hit'), ref = el('a', 'ref', row[2]);
    ref.href = 'plays/' + play.code + '/' + row[0] + '.html#' + row[1];
    li.appendChild(ref);
    li.appendChild(el('span', 'spk', row[3] === null ? '' : line.speakers[row[3]]));
    var text = el('span', row[4] === 's' ? 'line stage' : 'line');
    highlight(text, row[5]);
    li.appendChild(text);
    return li;
  }

  // Built with text nodes, never innerHTML: the line text is data.
  function highlight(target, text) {
    text.split(/([\p{L}\p{M}\p{N}]+)/u).forEach(function (part, i) {
      var word = i % 2 === 1 && E.normalise(part);
      if (word && state.words.some(function (w) { return S.matches(word, w, state.mode); })) {
        target.appendChild(el('mark', null, part));
      } else if (part) {
        target.appendChild(document.createTextNode(part));
      }
    });
  }

  document.addEventListener('DOMContentLoaded', function () {
    form = document.querySelector('[data-search-form]');
    if (!form) return;
    results = document.querySelector('[data-search-results]');
    count = document.querySelector('[data-search-count]');
    facetsEl = document.querySelector('[data-search-facets]');
    form.hidden = false;
    var params = new URLSearchParams(root.location.search);
    form.elements.q.value = params.get('q') || '';
    if (params.get('mode') === 'word') form.elements.mode.value = 'word';
    form.addEventListener('submit', function (event) { event.preventDefault(); run(); });
    if (form.elements.q.value) run();
  });
})(typeof window !== 'undefined' ? window : globalThis);
