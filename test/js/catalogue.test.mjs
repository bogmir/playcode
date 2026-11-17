// The catalogue's record filter, run with `node --test`. site.js gives EMOTHE.normalise;
// catalogue.js, with no `document`, loads only its pure half.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const read = (path) => readFileSync(new URL(path, import.meta.url), 'utf8');
const context = vm.createContext({});
vm.runInContext(read('../../priv/static_site/site.js'), context);
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
  yes(hamlet, { t: 'tragedy' }); yes(hamlet, { t: 'emothe0010' }); yes(hamlet, { a: 'SHAKES' });
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
