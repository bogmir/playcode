export function lineAt(text, offset) {
  return text.slice(0, offset).split('\n').length - 1;
}

export function rangeOf(text, line) {
  const lines = text.split('\n');
  const index = Math.min(line, lines.length - 1);
  const start = lines.slice(0, index).reduce((sum, each) => sum + each.length + 1, 0);
  return [start, start + lines[index].replace(/\r$/, '').length];
}

export function nearestMarked(lines, line) {
  const before = lines.filter((marked) => marked <= line);
  if (before.length) return Math.max(...before);
  return lines.length ? Math.min(...lines) : null;
}
