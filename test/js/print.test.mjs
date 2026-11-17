// The full text's print button: text.html#print, the title page's link, prints once the
// page has loaded, whatever the browser lets the page do to its address from file://.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const script = readFileSync(new URL('../../priv/static_site/site.js', import.meta.url), 'utf8');

function page(hash, replaceState) {
  const on = {};
  const listen = (event, fn) => { (on[event] ||= []).push(fn); };
  const button = { hidden: true, addEventListener() {} };
  const prints = [];
  const document = {
    documentElement: { dataset: {} },
    querySelector: (selector) => (selector === '[data-print]' ? button : null),
    querySelectorAll: () => [],
    addEventListener: listen
  };
  const root = {
    document,
    addEventListener: listen,
    location: { hash, pathname: '/site/plays/X/text.html', search: '', href: 'file:///site/plays/X/text.html' + hash },
    history: { replaceState },
    print: () => prints.push(1),
    innerWidth: 1024
  };
  root.window = root;
  vm.runInContext(script, vm.createContext(Object.assign(root, { globalThis: root })));
  const fire = (event) => (on[event] || []).forEach((fn) => fn({}));
  return { fire, prints, button };
}

test('#print prints once the page has loaded, and drops the hash', () => {
  const addresses = [];
  const p = page('#print', (_state, _title, url) => addresses.push(url));
  p.fire('DOMContentLoaded');
  assert.equal(p.prints.length, 0);
  p.fire('load');
  assert.equal(p.prints.length, 1);
  assert.deepEqual(addresses, ['/site/plays/X/text.html']);
});

test('a browser that will not change a file:// address still prints', () => {
  const p = page('#print', () => { throw new Error('SecurityError'); });
  p.fire('DOMContentLoaded');
  p.fire('load');
  assert.equal(p.prints.length, 1);
});

test('without #print nothing prints until the button is pressed', () => {
  const p = page('', () => {});
  p.fire('DOMContentLoaded');
  p.fire('load');
  assert.equal(p.prints.length, 0);
  assert.equal(p.button.hidden, false);
});
