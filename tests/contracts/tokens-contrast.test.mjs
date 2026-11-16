// Every text and control colour pair in design/tokens.json meets WCAG 2.x AA (manual §16.8:
// "Contrast passes AA, verified rather than assumed"). Runs with `pnpm test:contracts`.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const { color } = JSON.parse(readFileSync(new URL("../../design/tokens.json", import.meta.url), "utf8"));
const get = (path) => path.split(".").reduce((node, key) => node[key], color);

function luminance(hex) {
  const lin = (c) => (c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4);
  const [r, g, b] = [1, 3, 5].map((i) => lin(parseInt(hex.slice(i, i + 2), 16) / 255));
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}
const ratio = (a, b) => {
  const [hi, lo] = [luminance(get(a)), luminance(get(b))].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
};

const TEXT = [
  ["ink.900", "paper"], ["ink.900", "card"], ["ink.900", "sunk"], ["ink.600", "paper"], ["ink.600", "card"],
  ["ink.600", "sunk"], ["ink.400", "paper"], ["ink.400", "card"], ["card", "ink.900"], ["card", "ink.950"],
  ["alert.600", "alert.50"], ["alert.600", "card"], ["alert.600", "paper"],
  // Signal (ADR-015): ink on the pink, deep pink on cream, white on deep pink.
  ["ink.900", "signal.500"], ["signal.deep", "paper"], ["signal.deep", "card"], ["card", "signal.deep"],
  ...["confirmed", "recent", "estimated", "unknown"].flatMap((t) => [
    [`truth.${t}`, `truthSurface.${t}`], [`truth.${t}`, "card"], [`truth.${t}`, "paper"],
  ]),
];
const NON_TEXT = [["rule.control", "card"], ["rule.control", "paper"], ["ink.900", "paper"]];

for (const [fg, bg] of TEXT) {
  test(`${fg} on ${bg} is at least 4.5:1`, () => assert.ok(ratio(fg, bg) >= 4.5, `${ratio(fg, bg).toFixed(2)}:1`));
}
for (const [fg, bg] of NON_TEXT) {
  test(`${fg} against ${bg} is at least 3:1 (WCAG 1.4.11)`, () => assert.ok(ratio(fg, bg) >= 3, `${ratio(fg, bg).toFixed(2)}:1`));
}
test("ink.950 stays darker than ink.900", () => assert.ok(luminance(get("ink.950")) < luminance(get("ink.900"))));
// Never white on Signal: card text on signal.500 fails AA, so it must not be in TEXT above.
test("card (white) text on signal.500 is below 4.5:1 and never used", () => {
  assert.ok(ratio("card", "signal.500") < 4.5, `${ratio("card", "signal.500").toFixed(2)}:1`);
  assert.ok(!TEXT.some(([fg, bg]) => fg === "card" && bg === "signal.500"));
});
test("the self-check matches the WCAG reference ratio", () => {
  color.__black = "#000000"; color.__white = "#FFFFFF";
  assert.equal(ratio("__black", "__white").toFixed(1), "21.0");
});
