// The browser half of the static site's search, run with `node --test`. site.js and
// search.js are plain browser scripts; vm runs them with no `document`, so only their
// pure functions load.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const read = (path) => readFileSync(new URL(path, import.meta.url), 'utf8');
const context = vm.createContext({});
vm.runInContext(read('../../priv/static_site/site.js'), context);
vm.runInContext(read('../../priv/static_site/search.js'), context);
const { EMOTHE } = context;
const S = EMOTHE.search;
const cases = JSON.parse(read('../fixtures/search_normalisation.json'));
const plain = (value) => JSON.parse(JSON.stringify(value)); // across vm realms

test('words match the build-time normaliser', () => {
  for (const c of cases.words) assert.deepEqual([...EMOTHE.words(c.text)], c.words, c.text);
});

test('shard keys and file names match the build', () => {
  for (const c of cases.shards) {
    assert.equal(S.shardKey(c.word), c.key);
    assert.equal(S.shardFile(c.key), c.file);
  }
});

test('quoted words are a phrase, and every word must occur', () => {
  assert.deepEqual(plain(S.parse('"la vida es" Sueño')), { words: ['sueño', 'la', 'vida', 'es'], phrases: [['la', 'vida', 'es']] });
});

test('a query of punctuation has no words', () => {
  assert.deepEqual(plain(S.parse('¿¡ "" !?')), { words: [], phrases: [] });
  assert.deepEqual(plain(S.parse('')), { words: [], phrases: [] });
});

test('starts-with matches a prefix, except a one-letter word, which matches whole', () => {
  assert.ok(S.matches('sueños', 'sueño', 'prefix'));
  assert.ok(!S.matches('sueños', 'sueño', 'word'));
  assert.ok(S.matches('y', 'y', 'prefix'));
  assert.ok(!S.matches('yo', 'y', 'prefix'));
});

test('a phrase must occur in order', () => {
  assert.ok(S.hasPhrase(['toda', 'la', 'vida', 'es', 'sueño'], ['la', 'vida'], 'word'));
  assert.ok(!S.hasPhrase(['vida', 'la'], ['la', 'vida'], 'word'));
});

// The map held the stage flag (0 or 1) until notes came: it now holds the hit's kind,
// which a note's number decides, so the facets need no line text.
test('hits gather every matching word of a shard and keep its kind', () => {
  // sueño: play 0, line 4, spoken; sueños: play 1, line 2, stage; suelo: play 0, line 9;
  // sueñan: play 1, its first note.
  const shard = { 'sueño': [0, 1, 8], 'sueños': [1, 1, 5], 'suelo': [0, 1, 18], 'sueñan': [1, 1, S.NOTE_BASE * 2] };
  assert.deepEqual(plain(S.hits(shard, 'sueño', 'prefix')), { '0:4': 'spoken', '1:2': 'stage' });
  assert.deepEqual(plain(S.hits(shard, 'sueñan', 'word')), { ['1:' + S.NOTE_BASE]: 'note' });
  assert.deepEqual(plain(S.hits(undefined, 'sueño', 'prefix')), {});
  assert.deepEqual(plain(S.intersect([{ '0:4': 'spoken', '1:2': 'stage' }, { '0:4': 'spoken' }])), { '0:4': 'spoken' });
  assert.deepEqual(plain(S.intersect([])), {});
});

test('a note is told by its number: at or past NOTE_BASE, whatever its flag', () => {
  assert.equal(S.NOTE_BASE, cases.note_base);
  assert.equal(S.kind(4, 0), 'spoken');
  assert.equal(S.kind(4, 1), 'stage');
  assert.equal(S.kind(S.NOTE_BASE - 1, 1), 'stage');
  assert.equal(S.kind(S.NOTE_BASE, 0), 'note');
  assert.equal(S.kind(S.NOTE_BASE + 250, 0), 'note');
});

test('postings decode play by play from line deltas', () => {
  assert.deepEqual(plain(S.decode([0, 2, 8, 5, 3, 1, 0])), [[0, 4, 0], [0, 6, 1], [3, 0, 0]]);
  assert.deepEqual(plain(S.decode([])), []);
});

test('a line is looked up in the chunk the build wrote it to', () => {
  assert.equal(S.LINES_PER_CHUNK, cases.lines_per_chunk);
  assert.equal(S.chunkKey('EMOTHE0001', 0), 'EMOTHE0001/0');
  assert.equal(S.chunkKey('EMOTHE0001', 99), 'EMOTHE0001/0');
  assert.equal(S.chunkKey('EMOTHE0001', 100), 'EMOTHE0001/1');
  // A play's notes are in their own files, n0, n1, …
  assert.equal(S.chunkKey('EMOTHE0001', S.NOTE_BASE), 'EMOTHE0001/n0');
  assert.equal(S.chunkKey('EMOTHE0001', S.NOTE_BASE + 99), 'EMOTHE0001/n0');
  assert.equal(S.chunkKey('EMOTHE0001', S.NOTE_BASE + 100), 'EMOTHE0001/n1');
});
