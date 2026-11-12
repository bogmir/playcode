// The interface's language switch: the build writes each attribute in Spanish with its
// English in data-en-<name>; EMOTHE.translate swaps them in, and back.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

// An element with just the attribute methods translate uses.
function element(attributes, text = '') {
  const attrs = new Map(Object.entries(attributes));
  return {
    textContent: text,
    get attributes() { return [...attrs].map(([name, value]) => ({ name, value })); },
    getAttribute: (name) => attrs.get(name) ?? null,
    setAttribute: (name, value) => attrs.set(name, String(value)),
    hasAttribute: (name) => attrs.has(name)
  };
}

const nav = element({ 'aria-label': 'Índice', 'data-en-aria-label': 'Contents', 'data-tr': '' });
const title = element({ 'data-en-text': 'Search — EMOTHE', 'data-tr': '' }, 'Buscar — EMOTHE');
const html = { dataset: { ui: 'es' } };

const document = {
  documentElement: html,
  addEventListener() {},
  querySelectorAll: (selector) => (selector === '[data-tr]' ? [nav, title] : [])
};
const context = vm.createContext({ document });
vm.runInContext(readFileSync(new URL('../../priv/static_site/site.js', import.meta.url), 'utf8'), context);
const { translate, say } = context.EMOTHE;

test('English puts each attribute\'s English in place, and the title\'s text', () => {
  translate('en');
  assert.equal(nav.getAttribute('aria-label'), 'Contents');
  assert.equal(title.textContent, 'Search — EMOTHE');
});

test('Spanish puts back what the page was built with', () => {
  translate('en');
  translate('es');
  assert.equal(nav.getAttribute('aria-label'), 'Índice');
  assert.equal(title.textContent, 'Buscar — EMOTHE');
});

test('a message from the script follows the page\'s language', () => {
  html.dataset.ui = 'es';
  assert.equal(say('Copiado', 'Copied'), 'Copiado');
  html.dataset.ui = 'en';
  assert.equal(say('Copiado', 'Copied'), 'Copied');
});
