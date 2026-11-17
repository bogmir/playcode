/* EMOTHE static edition: the catalogue's search, over search/records.js and, for words in
   its text box, search.js. Loaded only by index.html, after site.js (EMOTHE.normalise). */
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
    return (list || []).filter(function (v) { return v !== null && v !== undefined; }).map(E.normalise);
  }

  // The entry of spec 7.4 with every text value a list of normalised strings, every range
  // a pair, and each witness and performance a tuple of the same.
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

  // Each filter: its name in the form and the address, how it matches, and where it reads
  // in the prepared entry, or in one of its witnesses (w) or performances (r).
  var FIELDS = {
    '': [['t', 'text', 't'], ['a', 'text', 'a'], ['l', 'list', 'l'], ['o', 'list', 'o'], ['k', 'list', 'k'],
      ['s', 'list', 's'], ['f', 'list', 'f'], ['x', 'list', 'x'], ['d', 'range', 'd'], ['h', 'list', 'h'],
      ['p', 'text', 'p'], ['n', 'text', 'n']],
    w: [['wt', 'list', 0], ['wc', 'text', 1], ['wy', 'range', 2], ['wf', 'list', 3]],
    r: [['rp', 'text', 0], ['rv', 'text', 1], ['rc', 'list', 2], ['ry', 'range', 3], ['rk', 'text', 4], ['ra', 'text', 5]]
  };

  // A range is "from-to", "from-" or "-to"; one typed backwards matches nothing, and a value
  // with no year matches no range.
  var TESTS = {
    text: function (have, want) {
      want = E.normalise(want);
      return have.some(function (v) { return v.indexOf(want) !== -1; });
    },
    list: function (have, want) { return have === want; },
    range: function (have, want) {
      var ends = want.split('-'), from = ends[0] ? Number(ends[0]) : -Infinity, to = ends[1] ? Number(ends[1]) : Infinity;
      return have[0] !== null && have[0] !== undefined && from <= to && have[1] >= from && have[0] <= to;
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

  if (!root.document) return;
})(typeof window !== 'undefined' ? window : globalThis);
