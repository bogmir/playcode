// The comparison pages' scroll sync, run with `node --test`. Each panel lists its
// speeches by act key in reading order; matchSpeech finds the other panel's speech for
// the one at the top of the panel being scrolled.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { counterpart, matchSpeech } from '../../assets/js/sync_scroll.mjs';

test('a speech pairs with the one the same way through the same act', () => {
  const source = ['act-0', 'act-0', 'act-0', 'act-1'];
  const target = ['act-0', 'act-0', 'act-1', 'act-1', 'act-1'];

  assert.equal(matchSpeech(source, target, 0), 0); // first of act 0
  assert.equal(matchSpeech(source, target, 2), 1); // last of act 0, which has two there
  assert.equal(matchSpeech(source, target, 3), 2); // act 1 restarts the count
});

test('an act the other edition lacks falls back to the whole play', () => {
  const fiveActs = ['act-0', 'act-1', 'act-2'];
  const oneDivision = ['act-0', 'act-0', 'act-0', 'act-0'];

  assert.equal(matchSpeech(fiveActs, oneDivision, 1), 2); // halfway: 1 of 0..2 is 2 of 0..3
  assert.equal(matchSpeech(fiveActs, oneDivision, 2), 3);
});

test('the first and last speeches pair with the first and last', () => {
  for (const [n, m] of [[10, 3], [3, 10], [7, 7]]) {
    assert.equal(counterpart(0, n, m), 0);
    assert.equal(counterpart(n - 1, n, m), m - 1);
  }
});

test('a lone speech pairs with the first, and an empty panel with nothing', () => {
  assert.equal(counterpart(0, 1, 5), 0);
  assert.equal(matchSpeech(['act-0'], [], 0), null);
});
