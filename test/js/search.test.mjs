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

test('hits gather every matching word of a shard and keep the stage flag', () => {
  const shard = { 'sueño': [0, 4, 0], 'sueños': [1, 2, 1], 'suelo': [0, 9, 0] };
  assert.deepEqual(plain(S.hits(shard, 'sueño', 'prefix')), { '0:4': 0, '1:2': 1 });
  assert.deepEqual(plain(S.hits(undefined, 'sueño', 'prefix')), {});
  assert.deepEqual(plain(S.intersect([{ '0:4': 0, '1:2': 1 }, { '0:4': 0 }])), { '0:4': 0 });
  assert.deepEqual(plain(S.intersect([])), {});
});
