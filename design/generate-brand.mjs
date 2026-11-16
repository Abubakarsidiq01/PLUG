// Exports the checked-in brand masters (design/brand/*.svg) to every place that uses them.
// Uses sharp, already installed with Next.js; no network requests.
//   node design/generate-brand.mjs          both targets
//   node design/generate-brand.mjs --web    design/brand/app-icon/ PNG set + web favicon, icons, manifest
//   node design/generate-brand.mjs --ios    the iOS asset catalog (PlugMark, PlugLogotype, AppIcon light/dark/tinted)
// The masters themselves are built by design/brand/build-masters.py (ink and paper from tokens.json).
import { createRequire } from "node:module";
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";

const webRequire = createRequire(new URL("../web/package.json", import.meta.url));
const sharp = createRequire(webRequire.resolve("next/package.json"))("sharp");
const tokens = JSON.parse(readFileSync(new URL("tokens.json", import.meta.url)));
const flat = (node) => (typeof node === "string" ? [node] : Object.values(node).flatMap(flat));
const palette = new Set(flat(tokens.color).map((hex) => hex.toUpperCase()).concat(["#000000", "#FFFFFF"]));
const args = process.argv.slice(2);
const want = (target) => args.length === 0 || args.includes(`--${target}`);

const brand = (file) => {
  const svg = readFileSync(new URL(`brand/${file}`, import.meta.url), "utf8");
  for (const [hex] of svg.matchAll(/#[A-Fa-f0-9]{6}/g)) {
    if (!palette.has(hex.toUpperCase())) throw new Error(`${file}: ${hex} is not a token colour`);
  }
  return svg;
};
const png = (svg, size, path) => sharp(Buffer.from(svg), { density: 300 }).resize(size, size).png().toFile(path);

// A .ico holding PNG images (supported by every current browser).
function ico(pngs) {
  const header = Buffer.alloc(6 + 16 * pngs.length);
  header.writeUInt16LE(1, 2);
  header.writeUInt16LE(pngs.length, 4);
  let offset = header.length;
  pngs.forEach(({ size, data }, i) => {
    const entry = 6 + 16 * i;
    header.writeUInt8(size % 256, entry);
    header.writeUInt8(size % 256, entry + 1);
    header.writeUInt16LE(1, entry + 4);
    header.writeUInt16LE(32, entry + 6);
    header.writeUInt32LE(data.length, entry + 8);
    header.writeUInt32LE(offset, entry + 12);
    offset += data.length;
  });
  return Buffer.concat([header, ...pngs.map((p) => p.data)]);
}

if (want("web")) {
  // Every iOS icon size, for App Store Connect and anyone who needs a raster.
  const set = new URL("brand/app-icon/", import.meta.url);
  mkdirSync(set, { recursive: true });
  const icon = brand("app-icon.svg");
  for (const size of [20, 29, 40, 58, 60, 76, 80, 87, 120, 152, 167, 180, 1024]) {
    await png(icon, size, new URL(`AppIcon-${size}.png`, set).pathname);
  }
  // Web: favicon.ico (16/32/48 from the small-size cut), SVG icon, Apple touch icon, PWA icons.
  const app = new URL("../web/src/app/", import.meta.url);
  const pub = new URL("../web/public/", import.meta.url);
  const small = brand("plug-mark-small.svg");
  const favicon = await Promise.all([16, 32, 48].map(async (size) => ({
    size, data: await sharp(Buffer.from(small), { density: 300 }).resize(size, size).png().toBuffer(),
  })));
  writeFileSync(new URL("favicon.ico", app), ico(favicon));
  writeFileSync(new URL("icon.svg", app), small);
  await png(icon, 180, new URL("apple-icon.png", app).pathname);
  await png(icon, 192, new URL("icon-192.png", pub).pathname);
  await png(icon, 512, new URL("icon-512.png", pub).pathname);
  console.log("Exported the app icon set and the web icons.");
}

if (want("ios")) {
  const catalog = new URL("../ios/Plug/Resources/Assets.xcassets/", import.meta.url);
  for (const [name, file] of [["PlugMark", "plug-mark.svg"], ["PlugLogotype", "plug-logotype.svg"], ["Neighbourhood", "neighbourhood.svg"]]) {
    const dir = new URL(`${name}.imageset/`, catalog);
    mkdirSync(dir, { recursive: true });
    writeFileSync(new URL(file, dir), brand(file));
    writeFileSync(new URL("Contents.json", dir), JSON.stringify({
      images: [{ filename: file, idiom: "universal" }],
      info: { author: "xcode", version: 1 },
      // Not template-rendered: PlugMark is also the launch-screen image, which the system would tint.
      properties: { "preserves-vector-representation": true },
    }, null, 2) + "\n");
  }
  const icons = new URL("AppIcon.appiconset/", catalog);
  const appearances = [["AppIcon.png", "app-icon.svg", null], ["AppIcon-Dark.png", "app-icon-dark.svg", "dark"], ["AppIcon-Tinted.png", "app-icon-tinted.svg", "tinted"]];
  for (const [out, file] of appearances) await png(brand(file), 1024, new URL(out, icons).pathname);
  writeFileSync(new URL("Contents.json", icons), JSON.stringify({
    images: appearances.map(([filename, , value]) => ({
      ...(value ? { appearances: [{ appearance: "luminosity", value }] } : {}),
      filename, idiom: "universal", platform: "ios", size: "1024x1024",
    })),
    info: { author: "xcode", version: 1 },
  }, null, 2) + "\n");
  console.log("Exported PlugMark, PlugLogotype and the app icon (light, dark, tinted) to the iOS asset catalog.");
}
