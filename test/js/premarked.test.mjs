// The premarked page's text box and preview: which line the caret is on, where a line
// starts and ends, and which line of the preview stands for it.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { lineAt, rangeOf, nearestMarked, lineAtHeight } from '../../assets/js/premarked.mjs';

test('the line a caret offset is on', () => {
  assert.equal(lineAt('a\nbb\nc', 0), 0);
  assert.equal(lineAt('a\nbb\nc', 3), 1);
  assert.equal(lineAt('a\nbb\nc', 5), 2);
  assert.equal(lineAt('a\r\nb', 3), 1);
});

test("a line's offsets, its newline left out", () => {
  assert.deepEqual(rangeOf('a\nbb\nc', 1), [2, 4]);
  assert.deepEqual(rangeOf('a\nbb\nc', 0), [0, 1]);
  assert.deepEqual(rangeOf('a\r\nbb', 1), [3, 5]);
});

test('a line past the end is the last one', () => {
  assert.deepEqual(rangeOf('a\nbb', 9), [2, 4]);
});

test('the marked line nearest before a line, else the first after it', () => {
  assert.equal(nearestMarked([2, 5, 9], 6), 5);
  assert.equal(nearestMarked([2, 5, 9], 5), 5);
  assert.equal(nearestMarked([2, 5], 0), 2);
  assert.equal(nearestMarked([], 3), null);
});

test('the line at a scroll height, from where each wrapped line starts', () => {
  const tops = [0, 20, 60, 80];
  assert.equal(lineAtHeight(tops, 0), 0);
  assert.equal(lineAtHeight(tops, 59), 1);
  assert.equal(lineAtHeight(tops, 60), 2);
  assert.equal(lineAtHeight(tops, 500), 3);
  assert.equal(lineAtHeight([], 10), 0);
});
