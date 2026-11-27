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

export function lineAtHeight(tops, y) {
  let low = 0;
  let high = tops.length - 1;
  while (low < high) {
    const middle = Math.ceil((low + high) / 2);
    if (tops[middle] <= y) low = middle;
    else high = middle - 1;
  }
  return Math.max(low, 0);
}

export function spanAt(starts, y) {
  const index = lineAtHeight(starts, y);
  const [start, end] = [starts[index] ?? 0, starts[index + 1] ?? starts[index] ?? 0];
  return { index, fraction: end > start ? Math.min(1, Math.max(0, (y - start) / (end - start))) : 0 };
}

export function heightAt(starts, index, fraction) {
  const [start, end] = [starts[index] ?? 0, starts[index + 1] ?? starts[index] ?? 0];
  return start + fraction * (end - start);
}
