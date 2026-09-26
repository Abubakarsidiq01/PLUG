// Export the checked-in vector identity into the native asset catalog.
// Uses the image renderer already installed with Next.js; no network requests.
import { createRequire } from 'node:module';
import { readFileSync, writeFileSync } from 'node:fs';
const webRequire = createRequire(new URL('../web/package.json', import.meta.url));
const sharp = createRequire(webRequire.resolve('next/package.json'))('sharp');
const tokens = JSON.parse(readFileSync(new URL('tokens.json', import.meta.url)));
const palette = new Set(Object.values(tokens.color).flatMap(Object.values));
const catalog = new URL('../ios/Plug/Resources/Assets.xcassets/', import.meta.url);
for (const [name, file] of [['PlugMark', 'plug-mark.svg'], ['Neighbourhood', 'neighbourhood.svg']]) {
  const svg = readFileSync(new URL(`brand/${file}`, import.meta.url), 'utf8');
  for (const match of svg.matchAll(/#[A-Fa-f0-9]{6}/g)) {
    if (!palette.has(match[0])) throw new Error(`Artwork colour is outside shared tokens: ${match[0]}`);
  }
  writeFileSync(new URL(`${name}.imageset/${file}`, catalog), svg);
}
const mark = readFileSync(new URL('brand/plug-mark.svg', import.meta.url), 'utf8')
  .replace('<svg ', '<svg x="232" y="232" width="560" height="560" ');
const icon = `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024"><rect width="1024" height="1024" fill="${tokens.color.surface['0']}"/>${mark}</svg>`;
await sharp(Buffer.from(icon)).png().toFile(new URL('AppIcon.appiconset/AppIcon.png', catalog).pathname);
console.log('Exported PLUG vector assets and app icon.');
