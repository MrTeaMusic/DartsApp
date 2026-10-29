#!/usr/bin/env node
// Erzeugt alle App-Icons (Windows, macOS, iOS, Android/Lite) und die SVG-Master.
//
//   node tools/app_icons/generate.mjs
//
// Voraussetzung: Node 18+ und Playwright mit Chromium (global oder im
// NODE_PATH). Es kommt keine Abhängigkeit in pubspec.yaml oder ins Repo. Mehr
// dazu in docs/app-icons.md.
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { iconSvg } from './icon_svg.mjs';
import { buildIco, stripAlpha } from './png.mjs';

const require = createRequire(import.meta.url);
const { chromium } = require('playwright');
const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..', '..');
const res = (...p) => path.join(root, ...p);

const browser = await chromium.launch();
const page = await browser.newPage({ deviceScaleFactor: 1 });

async function render(opts) {
  const { size } = opts;
  await page.setViewportSize({ width: size, height: size });
  await page.setContent(`<html><body style="margin:0;background:transparent">${iconSvg(opts)}</body></html>`);
  return page.screenshot({ omitBackground: true, clip: { x: 0, y: 0, width: size, height: size } });
}
const write = (file, buf) => {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, buf);
  console.log('  ' + path.relative(root, file));
};

// ---- SVG-Master (1024 px, Referenz; die Erzeugung nutzt je Größe die passende Detailstufe)
console.log('SVG-Master');
const masterDir = path.join(here, 'master');
write(path.join(masterDir, 'dartlab.svg'), Buffer.from(iconSvg({ fmt: 'ios', size: 1024, text: true })));
write(path.join(masterDir, 'dartlab-bogen.svg'), Buffer.from(iconSvg({ fmt: 'ios', size: 1024, text: false })));
write(path.join(masterDir, 'lite.svg'), Buffer.from(iconSvg({ lite: true, fmt: 'ios', size: 1024 })));

// ---- Windows (DartLab): PNG-eingebettete ICO
console.log('Windows');
const icoSizes = [16, 24, 32, 48, 64, 128, 256];
const icoImages = [];
for (const size of icoSizes) icoImages.push({ size, png: await render({ fmt: 'win', size }) });
write(res('windows/runner/resources/app_icon.ico'), buildIco(icoImages));

// ---- macOS (DartLab): Dateinamen aus Contents.json
console.log('macOS');
const macDir = res('macos/Runner/Assets.xcassets/AppIcon.appiconset');
const macFiles = new Set(JSON.parse(fs.readFileSync(path.join(macDir, 'Contents.json'), 'utf8')).images.map((i) => i.filename));
for (const name of macFiles) {
  const size = Number(/app_icon_(\d+)\.png/.exec(name)[1]);
  write(path.join(macDir, name), await render({ fmt: 'mac', size }));
}

// ---- iOS (DartLab): volles Quadrat ohne Alphakanal
console.log('iOS');
const iosDir = res('ios/Runner/Assets.xcassets/AppIcon.appiconset');
const iosImages = JSON.parse(fs.readFileSync(path.join(iosDir, 'Contents.json'), 'utf8')).images;
const done = new Set();
for (const img of iosImages) {
  if (done.has(img.filename)) continue;
  done.add(img.filename);
  const size = Math.round(parseFloat(img.size) * parseInt(img.scale, 10));
  write(path.join(iosDir, img.filename), stripAlpha(await render({ fmt: 'ios', size })));
}

// ---- Android (nur Lite, ohne Schriftzug): adaptive Ebenen, Themed-Icon, Altgeräte
console.log('Android (Lite)');
const dens = { mdpi: 1, hdpi: 1.5, xhdpi: 2, xxhdpi: 3, xxxhdpi: 4 };
const androidRes = res('android/app/src/main/res');
for (const [d, k] of Object.entries(dens)) {
  const layer = Math.round(108 * k), legacy = Math.round(48 * k);
  write(path.join(androidRes, `drawable-${d}`, 'ic_launcher_background.png'), stripAlpha(await render({ lite: true, fmt: 'andBg', size: layer })));
  write(path.join(androidRes, `drawable-${d}`, 'ic_launcher_foreground.png'), await render({ lite: true, fmt: 'andFg', size: layer }));
  write(path.join(androidRes, `drawable-${d}`, 'ic_launcher_monochrome.png'), await render({ lite: true, fmt: 'mono', size: layer }));
  write(path.join(androidRes, `mipmap-${d}`, 'ic_launcher.png'), await render({ lite: true, fmt: 'legacy', size: legacy }));
}
write(path.join(androidRes, 'mipmap-anydpi-v26', 'ic_launcher.xml'), Buffer.from(`<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background"/>
    <foreground android:drawable="@drawable/ic_launcher_foreground"/>
    <monochrome android:drawable="@drawable/ic_launcher_monochrome"/>
</adaptive-icon>
`));

await browser.close();
console.log('Fertig.');
