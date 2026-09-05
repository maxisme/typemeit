// Generates web/styles/theme.css (Tailwind v4 @theme) and
// TypeMeIt/DesignTokens.swift from design/tokens.json.
//
//   node design/build-tokens.mjs        from the repo root
//   npm run tokens                      from web/

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const t = JSON.parse(readFileSync(join(root, 'design/tokens.json'), 'utf8'));

const isToken = ([k]) => !k.startsWith('$');
const entries = (o) => Object.entries(o).filter(isToken);
const fontStack = (list) => list.map((f) => (/[\s-]/.test(f) && !f.startsWith('-') ? `'${f}'` : f)).join(', ');

// --- Theme-dependent values live on --tmi-* and flip with the colour scheme.
const scheme = (name) =>
  [
    ...entries(t.color[name]).map(([k, v]) => `  --tmi-${k}: ${v};`),
    `  --tmi-shadow-lift: ${t.shadow.lift[name]};`,
  ].join('\n');

const lines = [];
lines.push(`/* Generated from design/tokens.json by design/build-tokens.mjs. Do not edit. */`);
lines.push(``);
lines.push(`:root {\n${scheme('light')}\n}`);
lines.push(``);
lines.push(`@media (prefers-color-scheme: dark) {\n  :root:not([data-theme='light']) {\n${scheme('dark').replace(/^/gm, '  ')}\n  }\n}`);
lines.push(``);
lines.push(`:root[data-theme='dark'] {\n${scheme('dark')}\n}`);
lines.push(``);

// --- @theme inline: utilities reference the --tmi-* vars so they follow the scheme.
// Defaults are wiped on purpose: a black-and-white system with red-500 still
// reachable is not black and white.
lines.push(`@theme inline {`);
lines.push(`  --color-*: initial;`);
lines.push(`  --font-*: initial;`);
lines.push(`  --text-*: initial;`);
lines.push(`  --radius-*: initial;`);
lines.push(`  --shadow-*: initial;`);
lines.push(`  --ease-*: initial;`);
lines.push(`  --tracking-*: initial;`);
lines.push(`  --leading-*: initial;`);
lines.push(``);
for (const [k] of entries(t.color.light)) lines.push(`  --color-${k}: var(--tmi-${k});`);
lines.push(``);
for (const [k, v] of entries(t.font).filter(([k]) => k !== 'swift')) lines.push(`  --font-${k}: ${fontStack(v)};`);
lines.push(``);
for (const [k, v] of entries(t.text)) {
  lines.push(`  --text-${k}: ${v.size};`);
  lines.push(`  --text-${k}--line-height: ${v.lineHeight};`);
  lines.push(`  --text-${k}--letter-spacing: ${v.tracking};`);
  lines.push(`  --text-${k}--font-weight: ${v.weight};`);
}
lines.push(``);
lines.push(`  --spacing: ${t.spacing.unit};`);
lines.push(``);
for (const [k, v] of entries(t.radius)) lines.push(`  --radius-${k}: ${v};`);
lines.push(``);
lines.push(`  --shadow-lift: var(--tmi-shadow-lift);`);
lines.push(``);
for (const [k, v] of entries(t.motion.ease)) lines.push(`  --ease-${k}: ${v};`);
for (const [k, v] of entries(t.motion.duration)) lines.push(`  --duration-${k}: ${v};`);
lines.push(``);
lines.push(`  --hairline: ${t.hairline};`);
lines.push(`  --focus-width: ${t.focus.width};`);
lines.push(`  --focus-offset: ${t.focus.offset};`);
lines.push(`}`);
lines.push(``);

const out = join(root, 'web/styles/theme.css');
mkdirSync(dirname(out), { recursive: true });
writeFileSync(out, lines.join('\n'));
console.log(`wrote ${out}`);

// --- Swift. Colours are NSColor dynamic providers so they flip with the
// appearance the way the CSS does; type is Font.system with the fixed
// swiftSize; lengths are CGFloat in points (the web unit is 1px, so the
// numbers match).
const ident = (k) => k.replace(/-([a-z0-9])/g, (_, c) => c.toUpperCase()).replace(/^(\d)/, 'n$1');
const rgba = (v) => {
  const m = v.match(/^#([0-9a-f]{6})$/i);
  if (m) {
    const n = parseInt(m[1], 16);
    return [n >> 16, (n >> 8) & 255, n & 255].map((c) => (c / 255).toFixed(4)).concat('1');
  }
  const [r, g, b, a] = v.match(/[\d.]+/g);
  return [r, g, b].map((c) => (c / 255).toFixed(4)).concat(Number(a).toFixed(2));
};
const nsColor = (v) => {
  const [r, g, b, a] = rgba(v);
  return `NSColor(srgbRed: ${r}, green: ${g}, blue: ${b}, alpha: ${a})`;
};
const weightName = { 400: 'regular', 500: 'medium', 600: 'semibold', 700: 'bold' };
const ms = (v) => (parseFloat(v) / 1000).toFixed(3);

const sw = [];
sw.push(`// Generated from design/tokens.json by design/build-tokens.mjs. Do not edit.`);
sw.push(``);
sw.push(`import AppKit`);
sw.push(`import SwiftUI`);
sw.push(``);
sw.push(`enum DesignTokens {`);
sw.push(`    enum Colors {`);
sw.push(`        private static func dynamic(light: NSColor, dark: NSColor) -> Color {`);
sw.push(`            Color(nsColor: NSColor(name: nil) { appearance in`);
sw.push(`                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light`);
sw.push(`            })`);
sw.push(`        }`);
sw.push(``);
for (const [k, v] of entries(t.color.light)) {
  sw.push(`        static let ${ident(k)} = dynamic(light: ${nsColor(v)}, dark: ${nsColor(t.color.dark[k])})`);
}
sw.push(`    }`);
sw.push(``);
sw.push(`    enum Fonts {`);
for (const [k, v] of entries(t.text)) {
  const design = t.font.swift[v.family];
  sw.push(`        static let ${ident(k)} = Font.system(size: ${v.swiftSize}, weight: .${weightName[v.weight]}, design: .${design})`);
}
sw.push(`    }`);
sw.push(``);
sw.push(`    enum Tracking {`);
for (const [k, v] of entries(t.text)) {
  sw.push(`        static let ${ident(k)}: CGFloat = ${(parseFloat(v.tracking) * v.swiftSize).toFixed(2)}`);
}
sw.push(`    }`);
sw.push(``);
sw.push(`    enum Radius {`);
for (const [k, v] of entries(t.radius)) sw.push(`        static let ${ident(k)}: CGFloat = ${parseFloat(v)}`);
sw.push(`    }`);
sw.push(``);
sw.push(`    static let hairline: CGFloat = ${parseFloat(t.hairline)}`);
sw.push(`    static let focusWidth: CGFloat = ${parseFloat(t.focus.width)}`);
sw.push(`    static let focusOffset: CGFloat = ${parseFloat(t.focus.offset)}`);
sw.push(``);
sw.push(`    enum Duration {`);
for (const [k, v] of entries(t.motion.duration)) sw.push(`        static let ${ident(k)}: TimeInterval = ${ms(v)}`);
sw.push(`    }`);
sw.push(`}`);
sw.push(``);

const swiftOut = join(root, 'TypeMeIt/DesignTokens.swift');
writeFileSync(swiftOut, sw.join('\n'));
console.log(`wrote ${swiftOut}`);
