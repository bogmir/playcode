// The arrows that step through the shared lines and the stage directions, on the site
// and the play page: EMOTHE.step picks the next or previous one from the scroll position.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const context = vm.createContext({});
vm.runInContext(readFileSync(new URL('../../priv/static_site/site.js', import.meta.url), 'utf8'), context);
const { step } = context.EMOTHE;

test('the one on the reading line is the current one: next and previous step past it', () => {
  const tops = [-50, 10, 300, 900];
  assert.equal(step(tops, 300, 1), 3);
  assert.equal(step(tops, 300, -1), 1);
});

test('a pixel off the line, from rounding, still counts as on it', () => {
  assert.equal(step([10, 300.5, 900], 300, 1), 2);
  assert.equal(step([10, 299.5, 900], 300, -1), 0);
});

test('from between two, next is the one below and previous the one above', () => {
  assert.equal(step([-50, 10, 600], 300, 1), 2);
  assert.equal(step([-50, 10, 600], 300, -1), 1);
});

test('past the last, before the first, or with none, there is nowhere to go', () => {
  assert.equal(step([-50, 10], 300, 1), -1);
  assert.equal(step([400, 900], 300, -1), -1);
  assert.equal(step([], 300, 1), -1);
  assert.equal(step([], 300, -1), -1);
});

// The site scrolls smoothly: a second press comes before the first one's scroll ends, so
// while the current one is on screen the arrows step from it, not from the scroll.
test('from a current one on screen, the next and previous are its neighbours', () => {
  const tops = [100, 2000, 2100];
  assert.equal(step(tops, 300, 1, 0), 1);
  assert.equal(step(tops, 300, -1, 1), 0);
  assert.equal(step(tops, 300, 1, 2), -1);
  assert.equal(step(tops, 300, -1, 0), -1);
});

// EMOTHE.stepper against a page of three targets, the least DOM it touches.
function page(texts) {
  const el = (props) => ({
    attrs: {}, isConnected: true, dataset: {},
    setAttribute(k, v) { this.attrs[k] = v; }, removeAttribute(k) { delete this.attrs[k]; },
    getClientRects() { return [1]; }, scrollIntoView() {}, querySelector() { return null; },
    ...props,
  });
  const targets = texts.map((t, i) => el({ textContent: t, getBoundingClientRect: () => ({ top: 1000 * (i + 1), bottom: 1000 * (i + 1) + 20 }) }));
  const count = el({ textContent: '' });
  const said = el({ textContent: '' });
  const next = el({ dataset: { step: '1' } });
  let click;
  const box = el({
    dataset: { of: 'de' },
    querySelector: (s) => (s === '[data-step-count]' ? count : s === '[data-step-said]' ? said : null),
    addEventListener: (_type, fn) => { click = fn; },
  });
  const ctx = vm.createContext({ innerHeight: 800, document: { querySelectorAll: () => targets, addEventListener() {} } });
  vm.runInContext(readFileSync(new URL('../../priv/static_site/site.js', import.meta.url), 'utf8'), ctx);
  const stepper = ctx.EMOTHE.stepper(box, '.t');
  const press = () => click({ target: { closest: () => next } });
  return { targets, count, said, stepper, press };
}

test('a screen reader hears where the arrows landed, not only the count', () => {
  const p = page(['  ¿Quién   va?  ', 'Yo.', 'Ya.']);
  assert.equal(p.count.textContent, '– de 3');
  p.press();
  assert.equal(p.count.textContent, '1 de 3');
  assert.equal(p.said.textContent, '1 de 3: ¿Quién va?');
});

// LiveView drops attributes the browser set when it patches the page; a re-count puts
// the outline back on the one the arrows landed on.
test('a re-count keeps the outline on the current one', () => {
  const p = page(['uno', 'dos', 'tres']);
  p.press();
  delete p.targets[0].attrs['data-current'];
  p.stepper.refresh();
  assert.ok('data-current' in p.targets[0].attrs);
});
