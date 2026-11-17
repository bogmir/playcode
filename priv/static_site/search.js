/* EMOTHE static edition: full-text search over the files StaticSite.Search writes.
   Added by catalogue.js for words in the catalogue's text box, after site.js
   (EMOTHE.normalise, EMOTHE.words). Its page is the catalogue's. */
(function (root) {
  'use strict';
  var E = root.EMOTHE = root.EMOTHE || {};
  var S = E.search = E.search || {};
  var store = { plays: null, index: {}, lines: {} };
  var waiting = {};

  // Must match Playcode.Export.StaticSite.Search.lines_per_chunk/0 and note_base/0: a
  // play's notes are indexed after its lines, note i as entry NOTE_BASE + i.
  S.LINES_PER_CHUNK = 100;
  S.NOTE_BASE = 1000000;

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

  S.chunkKey = function (code, line) {
    return line >= S.NOTE_BASE
      ? code + '/n' + Math.floor((line - S.NOTE_BASE) / S.LINES_PER_CHUNK)
      : code + '/' + Math.floor(line / S.LINES_PER_CHUNK);
  };

  // What a hit is, from its posting alone: the facets are counted before any line loads.
  S.kind = function (line, flag) { return line >= S.NOTE_BASE ? 'note' : flag ? 'stage' : 'spoken'; };

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

  // Hits for one word: {"play:line": "spoken", "stage" or "note"}.
  S.hits = function (shard, word, mode) {
    var hits = {};
    Object.keys(shard || {}).forEach(function (token) {
      if (!S.matches(token, word, mode)) return;
      S.decode(shard[token]).forEach(function (h) { hits[h[0] + ':' + h[1]] = S.kind(h[1], h[2]); });
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

  // A query's hits by play: { CODE: [[line, kind], …] }, lines ascending; {} for no word.
  // mode is "prefix" or "word".
  S.find = function (query, mode) {
    var parsed = E.parse(query);
    if (!parsed.words.length) return Promise.resolve({});
    var keys = parsed.words.map(S.shardKey).filter(function (k, i, a) { return a.indexOf(k) === i; });
    return need('plays', 'all', 'search/plays.js')
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
        var out = {};
        pairsOf(hits).sort(function (a, b) { return a[1] - b[1]; }).forEach(function (pl) {
          var code = store.plays[pl[0]].code;
          (out[code] = out[code] || []).push([pl[1], hits[pl[0] + ':' + pl[1]]]);
        });
        return out;
      });
  };

  // The given lines of a play, as links to where they stand; a line whose chunk could not
  // be loaded is left out.
  S.passages = function (code, lines) {
    var p = store.plays.map(function (play) { return play.code; }).indexOf(code);
    var pairs = lines.map(function (l) { return [p, l]; });
    return loadLines(pairs).then(function () {
      return pairs.map(function (pl) { return lineOf(pl[0], pl[1]); }).filter(Boolean).map(function (line) {
        var row = line.row;
        return { href: 'plays/' + code + '/' + row[0] + '.html#' + row[1], ref: row[2],
          speaker: row[3] === null ? null : line.speakers[row[3]], kind: row[4], text: row[5] };
      });
    });
  };
})(typeof window !== 'undefined' ? window : globalThis);
