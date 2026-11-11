// The comparison pages' scroll sync, run with `node --test`. Each panel lists its
// speeches by act key in reading order; matchSpeech finds the other panel's speech for
// the one at the top of the panel being scrolled.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { counterpart, matchPair, matchSpeech, syncPanels } from '../../assets/js/sync_scroll.mjs';

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

// Problem 5: each speech carries the place of the original speech it goes with
// (data-pair), computed on the server; the other panel scrolls to the speech with the same
// pair, or to the next one when its edition cut that speech.
test('a speech scrolls to the speech with its pair, a cut one to the next', () => {
  const original = [0, 1, 2, 3];
  const french = [0, 1, 1, 3]; // splits speech 1, cuts speech 2

  assert.equal(matchPair(french, 1), 1); // the first half of the split
  assert.equal(matchPair(original, 1), 1);
  assert.equal(matchPair(french, 2), 3); // cut: the speech after it
  assert.equal(matchPair(french, 9), 3); // past the end: the last
  assert.equal(matchPair([], 0), null);
});

// Two panels of five speeches, 100px apart; requestAnimationFrame runs on flush().
function panels() {
  const queue = []
  globalThis.requestAnimationFrame = (cb) => queue.push(cb)
  const flush = () => { while (queue.length) queue.shift()() }
  const panel = () => {
    const p = new EventTarget()
    p.scrollTop = 0
    p.getBoundingClientRect = () => ({ top: 0 })
    const speeches = [0, 1, 2, 3, 4].map((i) => ({
      dataset: { syncAct: 'act-0', pair: String(i) },
      hasAttribute: (name) => name !== 'data-sync-div',
      getBoundingClientRect: () => ({ top: i * 100 - p.scrollTop }),
    }))
    p.querySelectorAll = () => speeches
    return p
  }
  const [a, b] = [panel(), panel()]
  syncPanels({ querySelectorAll: () => [a, b] })
  flush()
  const scroll = (p, top) => { p.scrollTop = top; p.dispatchEvent(new Event('scroll')); flush() }
  return { a, b, scroll }
}

// A touch pan fires pointercancel and pointerleave as soon as the browser takes the
// scroll over, and the panel still leads the scroll that follows.
test('a panel panned by touch still leads', () => {
  const { a, b, scroll } = panels()
  b.dispatchEvent(new Event('pointerenter'))
  b.dispatchEvent(new Event('pointercancel'))
  b.dispatchEvent(new Event('pointerleave'))
  scroll(b, 200)
  assert.equal(a.scrollTop, 200)
})

test('a panel scrolled from the keyboard leads', () => {
  const { a, b, scroll } = panels()
  b.dispatchEvent(new Event('focusin'))
  scroll(b, 300)
  assert.equal(a.scrollTop, 300)
})

// The pointer rests over a panel while the other has the focus: the wheel turns it back.
test('a panel turned by the wheel leads', () => {
  const { a, b, scroll } = panels()
  a.dispatchEvent(new Event('pointerenter'))
  b.dispatchEvent(new Event('focusin'))
  a.dispatchEvent(new Event('wheel'))
  scroll(a, 100)
  assert.equal(b.scrollTop, 100)
})
