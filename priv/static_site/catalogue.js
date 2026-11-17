/* EMOTHE static edition: the catalogue's search over search/records.js, and search.js for
   its text box. Loaded by index.html after site.js. */
(function (root) {
  'use strict';
  var E = root.EMOTHE = root.EMOTHE || {};
  var R = E.records = E.records || {};
  var waiting = [];

  // Called by search/records.js.
  R.load = function (entries) {
    R.entries = entries;
    waiting.splice(0).forEach(function (callback) { callback(entries); });
  };
  R.ready = function (callback) { if (R.entries) callback(R.entries); else waiting.push(callback); };

  function texts(list) {
    return (list || []).filter(function (v) { return v != null; }).map(E.normalise);
  }

  // Spec 7.4's entry with text as lists of normalised strings and ranges as pairs.
  R.prepare = function (e) {
    return {
      c: e.c, t: texts((e.t || []).concat(e.c)), a: texts([e.a]), l: e.l, o: e.o, k: e.k, s: e.s, f: e.f,
      x: e.x ? '1' : '0', d: e.d || [], h: e.h, p: texts([].concat.apply([], e.p || [])), n: texts(e.n),
      w: (e.w || []).map(function (w) { return [w[0], texts([w[1]]), [w[2], w[3]], w[4]]; }),
      r: (e.r || []).map(function (r) {
        return [texts(r[0]), texts([r[1]]), r[2], [r[3], r[4]], texts([r[5]]), texts(r[6])];
      })
    };
  };

  // Each filter: its name, how it matches, where it reads in the entry, a witness (w) or a performance (r).
  var FIELDS = {
    '': [['t', 'text', 't'], ['a', 'text', 'a'], ['l', 'list', 'l'], ['o', 'list', 'o'], ['k', 'list', 'k'],
      ['s', 'list', 's'], ['f', 'list', 'f'], ['x', 'list', 'x'], ['d', 'range', 'd'], ['h', 'list', 'h'],
      ['p', 'text', 'p'], ['n', 'text', 'n']],
    w: [['wt', 'list', 0], ['wc', 'text', 1], ['wy', 'range', 2], ['wf', 'list', 3]],
    r: [['rp', 'text', 0], ['rv', 'text', 1], ['rc', 'list', 2], ['ry', 'range', 3], ['rk', 'text', 4], ['ra', 'text', 5]]
  };

  // A range is "from-to", "from-" or "-to"; backwards matches nothing, nor does a value with no year.
  var TESTS = {
    text: function (have, want) {
      want = E.normalise(want);
      return have.some(function (v) { return v.indexOf(want) !== -1; });
    },
    list: function (have, want) { return have === want; },
    range: function (have, want) {
      var ends = want.split('-'), from = ends[0] ? Number(ends[0]) : -Infinity, to = ends[1] ? Number(ends[1]) : Infinity;
      return have[0] != null && from <= to && have[1] >= from && have[0] <= to;
    }
  };

  // What the state asks of a field: "" for nothing, a range with neither end included.
  function asked(state, name) { var v = String(state[name] || '').trim(); return v === '-' ? '' : v; }

  function meets(fields, row, state) {
    return fields.every(function (f) {
      var want = asked(state, f[0]);
      return !want || TESTS[f[1]](row[f[2]], want);
    });
  }

  // Filters combine with AND; a group's fields must all be met by one witness or one performance.
  R.match = function (entry, state) {
    return meets(FIELDS[''], entry, state) && ['w', 'r'].every(function (group) {
      var fields = FIELDS[group];
      return !fields.some(function (f) { return asked(state, f[0]); }) ||
        entry[group].some(function (row) { return meets(fields, row, state); });
    });
  };

  // The address's names, in the order it writes them.
  var NAMES = 't a l o k s f x q m in d wt wc wy wf rp rv rc ry rk ra h p n sort'.split(' ');

  // "#l=en&d=1600-" to { l: "en", d: "1600-" }; unknown names and undecodable values dropped.
  R.parse = function (hash) {
    var state = {};
    String(hash || '').replace(/^#/, '').split('&').forEach(function (pair) {
      var at = pair.indexOf('='), name = pair.slice(0, at);
      if (at < 0 || NAMES.indexOf(name) < 0) return;
      try { state[name] = decodeURIComponent(pair.slice(at + 1).replace(/\+/g, ' ')); } catch (e) { /* skip it */ }
    });
    return state;
  };

  R.format = function (state) {
    return NAMES.filter(function (name) { return String(state[name] || '').trim(); })
      .map(function (name) { return name + '=' + encodeURIComponent(state[name]); }).join('&');
  };

  // works: [[lead, code, …], …]. A work shows when any play passes; its lead stays, muted, to head it.
  R.shown = function (works, passing) {
    var rows = {}, count = 0;
    works.forEach(function (codes) {
      var any = codes.some(function (code) { return passing[code]; });
      codes.forEach(function (code, i) {
        if (passing[code]) count++;
        rows[code] = passing[code] ? 'show' : any && i === 0 ? 'muted' : 'hide';
      });
    });
    return { rows: rows, count: count };
  };

  // A passage cut by the words found into [[text, marked], …], as the search matches them.
  R.marked = function (text, words, mode) {
    var out = [];
    text.split(/([\p{L}\p{M}\p{N}]+)/u).forEach(function (part, i) {
      var mark = i % 2 === 1 && words.some(function (w) { return E.search.matches(E.normalise(part), w, mode); });
      var last = out[out.length - 1];
      if (!part) return;
      if (last && last[1] === mark) last[0] += part; else out.push([part, mark]);
    });
    return out;
  };

  // fn, run once a burst of calls pauses for ms: a search per word typed, not per letter.
  R.later = function (fn, ms) {
    var timer;
    return function () { clearTimeout(timer); timer = setTimeout(fn, ms); };
  };

  if (!root.document) return;

  // The page. It never decides a match: R.match and R.shown do.
  var RANGES = ['d', 'wy', 'ry'], NOT_RECORDS = ['q', 'm', 'in', 'sort'];
  var KINDS = { s: 'spoken', d: 'stage', n: 'note' }, FIRST = 5;
  // A datalist's values: where they are in an entry, or in its witnesses or performances.
  var SUGGEST = [['a', '', 'a'], ['wc', 'w', 1], ['rp', 'r', 0], ['rv', 'r', 1], ['rk', 'r', 5], ['ra', 'r', 6], ['p', '', 'p']];
  var form, list, count, W, works, rows, prepared, loading, engine, found, sorted = '';

  function say(pair) { return E.say(pair[0], pair[1]); }
  function each(selector, scope, fn) { scope.querySelectorAll(selector).forEach(fn); }

  // The form's controls, and those tied to it by form="search", into a state, and back.
  function read() {
    var state = {};
    NAMES.forEach(function (name) {
      var v = RANGES.indexOf(name) < 0 ? form.elements[name].value
        : (form.elements[name + '-from'].value + '-' + form.elements[name + '-to'].value).replace(/^-$/, '');
      if (v.trim()) state[name] = v;
    });
    return state;
  }

  function write(state) {
    NAMES.forEach(function (name) {
      var control = form.elements[name], v = state[name] || '';
      if (RANGES.indexOf(name) < 0) {
        // A value no published play holds (a link from another build) is kept, and finds none.
        if (control.tagName === 'SELECT' && v && !control.querySelector('option[value="' + CSS.escape(v) + '"]')) {
          control.appendChild(new Option(v, v));
        }
        control.value = v;
        return;
      }
      var ends = v.split('-');
      form.elements[name + '-from'].value = ends[0] || '';
      form.elements[name + '-to'].value = ends[1] || '';
    });
  }

  function recordsAsked(state) {
    return Object.keys(state).some(function (name) { return NOT_RECORDS.indexOf(name) < 0; });
  }

  function add(src) {
    var script = document.createElement('script');
    script.src = src;
    return document.head.appendChild(script);
  }

  function loadRecords() { if (!loading) loading = add('search/records.js'); }

  function flat(value, out) {
    if (Array.isArray(value)) value.forEach(function (v) { flat(v, out); });
    else if (value != null) out.push(value);
    return out;
  }

  function suggest(entries) {
    SUGGEST.forEach(function (s) {
      var seen = {}, datalist = document.getElementById('dl-' + s[0]);
      entries.forEach(function (e) {
        (s[1] ? e[s[1]] || [] : [e]).forEach(function (row) { flat(row[s[2]], []).forEach(function (v) { seen[v] = true; }); });
      });
      Object.keys(seen).sort(function (a, b) { return a.localeCompare(b); })
        .forEach(function (v) { datalist.appendChild(new Option('', v)); });
    });
  }

  function reorder(key) {
    if (key === sorted) return;
    key = (sorted = key) || 'author';
    Array.from(list.children).sort(function (a, b) {
      var x = a.dataset[key] || '', y = b.dataset[key] || '';
      if (x === y) return 0;
      if (key === 'date') { x = x ? Number(x) : Infinity; y = y ? Number(y) : Infinity; return x - y; }
      return x.localeCompare(y);
    }).forEach(function (item) { list.appendChild(item); });
  }

  function el(tag, cls, text) {
    var node = document.createElement(tag);
    if (cls) node.className = cls;
    if (text) node.textContent = text;
    return node;
  }

  function counted(n, one, many) { return n + ' ' + say(n === 1 ? W[one] : W[many]); }

  // search.js, added once with the assets' stamp, for words in the text box.
  function needEngine() {
    return engine = engine || new Promise(function (resolve) {
      var script = add('assets/search.js?v=' + form.dataset.assets);
      script.onload = script.onerror = resolve;
    });
  }

  function modeOf(state) { return state.m === 'w' ? 'word' : 'prefix'; }

  function textKey(state) { return (state.m || '') + ':' + (state.q || ''); }

  function search(state) {
    count.textContent = say(W.searching);
    needEngine().then(function () { return E.search && E.search.find(state.q, modeOf(state)); })
      .then(function (hits) {
        if (!hits) { count.textContent = say(W.unavailable); return; }
        // A search typed over by another is dropped: the later one shows.
        if (textKey(read()) !== textKey(state)) return;
        found = { key: textKey(state), hits: hits };
        filter(read());
      });
  }

  // A row's passages, folded: opened, its first lines load, and "show more" the rest.
  function passages(row, lines, state) {
    var details = el('details', 'passages'), words = E.search.parse(state.q).words;
    var mode = modeOf(state), shown = 0;
    details.appendChild(el('summary', null, say(W.open)));
    function more(n) {
      var next = lines.slice(shown, shown + n);
      shown += next.length;
      E.search.passages(row.dataset.code, next).then(function (found) {
        each('button', details, function (b) { b.remove(); });
        found.forEach(function (p) {
          var line = el('p'), link = el('a');
          link.href = p.href;
          link.appendChild(el('span', 'ref', [p.ref, p.speaker].filter(Boolean).join(' · ')));
          line.appendChild(link);
          // Built with text nodes, never innerHTML: the line text is data.
          R.marked(p.text, words, mode).forEach(function (piece) {
            line.appendChild(piece[1] ? el('mark', null, piece[0]) : document.createTextNode(piece[0]));
          });
          details.appendChild(line);
        });
        if (shown < lines.length) {
          var rest = el('button', 'more', say(W.more).replace('%{count}', lines.length - shown));
          rest.type = 'button';
          rest.onclick = function () { more(lines.length); };
          details.appendChild(rest);
        }
      });
    }
    details.ontoggle = function () { if (details.open && !shown) more(FIRST); };
    row.after(el('span', 'meta', counted(lines.length, 'passage', 'passages')), details);
    row.nextSibling.setAttribute('data-hits', '');
  }

  // Shows the rows the state lets through: every row until the records land; with words, only plays with hits.
  function filter(state) {
    var asked = recordsAsked(state), all = !asked || !prepared;
    var text = E.words(state.q || '').length > 0, kind = KINDS[state.in], lines = {};
    if (text && (!found || found.key !== textKey(state))) { search(state); return; }
    var passing = {};
    rows.forEach(function (row) {
      var code = row.dataset.code;
      lines[code] = text && (found.hits[code] || [])
        .filter(function (h) { return !kind || h[1] === kind; }).map(function (h) { return h[0]; });
      passing[code] = (all || !!prepared[code] && R.match(prepared[code], state)) && (!text || lines[code].length > 0);
    });
    each('[data-hits], .passages', list, function (node) { node.remove(); });
    var result = R.shown(works, passing);
    rows.forEach(function (row) {
      var shown = result.rows[row.dataset.code];
      row.hidden = shown === 'hide';
      row.classList.toggle('muted', shown === 'muted');
      if (text && passing[row.dataset.code]) passages(row, lines[row.dataset.code], state);
    });
    each('[data-work]', list, function (work) { work.hidden = !work.querySelector('[data-play]:not([hidden])'); });
    count.textContent = result.count === rows.length ? '' : counted(result.count, 'play', 'plays') + ' ' + say(W.of) + ' ' + rows.length;
  }

  function update() {
    var state = read(), address = R.format(state);
    try { root.history.replaceState(null, '', address ? '#' + address : root.location.pathname); } catch (e) { /* file:// may refuse */ }
    if (recordsAsked(state)) loadRecords();
    reorder(state.sort || '');
    filter(state);
  }

  R.ready(function (entries) {
    prepared = {};
    entries.forEach(function (e) { prepared[e.c] = R.prepare(e); });
    suggest(entries);
    filter(read());
  });

  document.addEventListener('DOMContentLoaded', function () {
    form = document.querySelector('form[data-search]');
    if (!form) return;
    list = document.querySelector('[data-works]');
    count = document.querySelector('[data-count]');
    W = JSON.parse(form.dataset.words);
    rows = Array.from(list.querySelectorAll('[data-play]'));
    works = Array.from(list.children, function (work) {
      return Array.from(work.querySelectorAll('[data-play]'), function (row) { return row.dataset.code; });
    });
    form.hidden = false;
    document.querySelector('[data-catalogue-controls]').hidden = false;
    write(R.parse(root.location.hash));
    // The text search and the sort are outside the form's element, tied by form="search".
    var typed = R.later(update, 300);
    ['input', 'change', 'focusin'].forEach(function (type) {
      document.addEventListener(type, function (event) {
        var target = event.target;
        if (target.form !== form) return;
        if (type === 'focusin') loadRecords(); else if (target.name === 'q') typed(); else update();
      });
    });
    form.addEventListener('reset', function () { setTimeout(update); });
    root.addEventListener('hashchange', function () { write(R.parse(root.location.hash)); update(); });
    document.addEventListener('emothe:ui', function () { filter(read()); });
    update();
  });
})(typeof window !== 'undefined' ? window : globalThis);
