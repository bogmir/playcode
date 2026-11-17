// The catalogue's record filter, run with `node --test`. site.js gives EMOTHE.normalise;
// catalogue.js, with no `document`, loads only its pure half.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const read = (path) => readFileSync(new URL(path, import.meta.url), 'utf8');
const context = vm.createContext({});
vm.runInContext(read('../../priv/static_site/site.js'), context);
vm.runInContext(read('../../priv/static_site/search.js'), context);   // EMOTHE.search.matches, for R.marked
vm.runInContext(read('../../priv/static_site/catalogue.js'), context);
const R = context.EMOTHE.records;
const plain = (value) => JSON.parse(JSON.stringify(value)); // across vm realms

const hamlet = { c: 'EMOTHE0010', t: ['Hamlet', 'The Tragedy of Hamlet'], a: 'William Shakespeare', l: 'es', o: 'en',
  k: 'translation', s: 'EMOTHE', f: 'verse', x: 1, d: [1599, 1601], h: 'edad_media',
  w: [['early_edition', 'London', 1604, 1605, '4º'], ['collection', 'Madrid', 1623, 1623, '2º'], ['manuscript', null, null, null, null]],
  r: [[['London', 'England', 'Inglaterra'], 'The Globe', 'commercial_theatre', 1601, 1601, 'The King’s Men', ['Richard Burbage']],
      [[], null, 'palace', 1619, 1620, null, []]],
  p: [['Elsinor', 'Elsinore', 'Dinamarca', 'Denmark']], n: ['HAMLET', 'OFELIA', 'Calderón'] };
const bare = { c: 'EMOTHE0596', t: ['L’abuseur de Séville'], l: 'fr', o: 'fr', k: 'original', s: 'EMOTHE' };
const yes = (entry, state) => assert.equal(R.match(R.prepare(entry), state), true, JSON.stringify(state));
const no = (entry, state) => assert.equal(R.match(R.prepare(entry), state), false, JSON.stringify(state));

test('an empty state matches every play', () => { yes(hamlet, {}); yes(bare, {}); });
test('text is a normalised substring', () => {
  yes(hamlet, { t: 'tragedy' }); yes(hamlet, { t: 'othe0010' }); yes(hamlet, { a: 'SHAKES' });
  yes(hamlet, { n: 'calderon' }); no(hamlet, { n: 'ofelio' }); yes(bare, { t: 'seville' });
  no(bare, { a: 'x' });                                   // no author matches no author text
});
test('ñ is not n', () => { no({ c: 'X', t: ['El año'] }, { t: 'ano' }); yes({ c: 'X', t: ['El año'] }, { t: 'AÑO' }); });
test('a list wants its value', () => {
  yes(hamlet, { l: 'es', o: 'en', k: 'translation', s: 'EMOTHE', f: 'verse', h: 'edad_media' });
  no(hamlet, { l: 'en' }); no(bare, { f: 'prose' }); no(bare, { h: 'edad_media' });
});
test('with or without text', () => { yes(hamlet, { x: '1' }); no(hamlet, { x: '0' }); yes(bare, { x: '0' }); no(bare, { x: '1' }); });
test('a range overlaps', () => {
  yes(hamlet, { d: '1601-1610' }); yes(hamlet, { d: '1590-' }); yes(hamlet, { d: '-1599' });
  no(hamlet, { d: '1602-' }); no(hamlet, { d: '1610-1600' }); no(bare, { d: '1500-1700' });   // backwards; no dating
});
test('witness fields are met by one witness', () => {
  yes(hamlet, { wt: 'early_edition', wc: 'london', wy: '1600-1610', wf: '4º' });
  no(hamlet, { wc: 'london', wf: '2º' });                  // London is the quarto, Madrid the folio
  no(hamlet, { wt: 'manuscript', wy: '1500-1700' });       // a witness with no year matches no range
  yes(hamlet, { wt: 'manuscript' });
});
test('performance fields are met by one performance', () => {
  yes(hamlet, { rp: 'inglaterra', rv: 'globe', rc: 'commercial_theatre', ry: '1601-1601', rk: 'king', ra: 'burbage' });
  no(hamlet, { rc: 'palace', rk: 'king' });
  yes(hamlet, { rc: 'palace', ry: '1620-' });
});
test('a place of action is found by any of its names, or a containing place', () => {
  yes(hamlet, { p: 'elsinore' }); yes(hamlet, { p: 'dinamarca' }); no(hamlet, { p: 'sevilla' });
});
test('filters combine with and', () => { no(hamlet, { l: 'es', n: 'nadie' }); });
test('q, m, in and sort are not record filters', () => { yes(bare, { q: 'honor', m: 'w', in: 'n', sort: 'date' }); });

test('the address round-trips, in the table’s order, empty values left out', () => {
  const state = { l: 'en', q: 'la vida', wy: '1600-1610', a: 'Calderón' };
  assert.equal(R.format(state), 'a=Calder%C3%B3n&l=en&q=la%20vida&wy=1600-1610');
  assert.deepEqual(plain(R.parse('#' + R.format(state))), state);
  assert.equal(R.format({ l: '', t: '  ' }), '');
  assert.deepEqual(plain(R.parse('#nope=1&l=en')), { l: 'en' });
  assert.deepEqual(plain(R.parse('')), {});
});
test('a malformed address is read as far as it goes', () => {
  assert.deepEqual(plain(R.parse('#t=%E0%A4&q=la+vida')), { q: 'la vida' });
});
test('a work shows when any of its plays passes; its lead stays, muted, to head it', () => {
  const works = [['A', 'A1', 'A2'], ['B'], ['C', 'C1']];
  assert.deepEqual(plain(R.shown(works, { A1: true, B: true })), {
    rows: { A: 'muted', A1: 'show', A2: 'hide', B: 'show', C: 'hide', C1: 'hide' }, count: 2 });
  assert.equal(R.shown(works, { A: true, A1: true, A2: true, B: true, C: true, C1: true }).count, 6);
});

test('a passage is cut into plain and marked pieces by the words found', () => {
  assert.deepEqual(plain(R.marked('¿Es un Sueño, la vida?', ['sueño'], 'prefix')),
    [['¿Es un ', false], ['Sueño', true], [', la vida?', false]]);
  assert.deepEqual(plain(R.marked('sueños y sueño', ['sueño'], 'word')), [['sueños y ', false], ['sueño', true]]);
  assert.deepEqual(plain(R.marked('nada', ['sueño'], 'prefix')), [['nada', false]]);
});

test('a burst of calls runs once, after the pause', () => {
  const pending = [];
  context.setTimeout = (fn) => pending.push(fn);
  context.clearTimeout = (id) => { pending[id - 1] = null; };
  let runs = 0;
  const later = R.later(() => runs++, 250);
  later(); later(); later();
  assert.equal(runs, 0);
  pending.filter(Boolean).forEach((fn) => fn());
  assert.equal(runs, 1);
});

test('a passage names its place; a note says it is one, and has no speaker', () => {
  // Kinds as search.ex writes them: v verse, p prose, s stage direction, n note.
  assert.equal(R.ref({ kind: 'v', ref: 'I, 63', speaker: 'CLARÍN' }, 'nota'), 'I, 63 · CLARÍN');
  assert.equal(R.ref({ kind: 's', ref: 'I, 63', speaker: null }, 'nota'), 'I, 63');
  assert.equal(R.ref({ kind: 'n', ref: 'IV, 971', speaker: 'DON FELIS' }, 'nota'), 'nota IV, 971');
});
