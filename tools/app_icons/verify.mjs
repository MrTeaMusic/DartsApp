#!/usr/bin/env node
// Prüft die erzeugten Icons: Dateien vorhanden, Größen stimmen, iOS ohne Alpha,
// ICO vollständig, Contents.json verweist nur auf vorhandene Dateien.
//
//   node tools/app_icons/verify.mjs
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { pngInfo, readIco } from './png.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const res = (...p) => path.join(root, ...p);
let errors = 0, checked = 0;
const fail = (m) => { errors++; console.error('FEHLER: ' + m); };
const png = (file, size, { noAlpha = false } = {}) => {
  checked++;
  if (!fs.existsSync(file)) return fail(`fehlt: ${path.relative(root, file)}`);
  const i = pngInfo(fs.readFileSync(file));
  if (i.width !== size || i.height !== size) fail(`${path.relative(root, file)}: ${i.width}x${i.height}, erwartet ${size}`);
  if (noAlpha && i.colorType !== 2) fail(`${path.relative(root, file)}: hat Alphakanal (Farbtyp ${i.colorType})`);
};

// iOS
const iosDir = res('ios/Runner/Assets.xcassets/AppIcon.appiconset');
const ios = JSON.parse(fs.readFileSync(path.join(iosDir, 'Contents.json'), 'utf8')).images;
for (const img of ios) png(path.join(iosDir, img.filename), Math.round(parseFloat(img.size) * parseInt(img.scale, 10)), { noAlpha: true });

// macOS
const macDir = res('macos/Runner/Assets.xcassets/AppIcon.appiconset');
for (const img of JSON.parse(fs.readFileSync(path.join(macDir, 'Contents.json'), 'utf8')).images) {
  png(path.join(macDir, img.filename), Number(/app_icon_(\d+)\.png/.exec(img.filename)[1]));
}

// Windows
const icoFile = res('windows/runner/resources/app_icon.ico');
const ico = readIco(fs.readFileSync(icoFile));
const got = ico.map((e) => e.width).sort((a, b) => a - b).join(',');
if (got !== '16,24,32,48,64,128,256') fail(`ICO-Größen: ${got}`);
for (const e of ico) if (e.width !== e.height || e.colorType !== 6) fail('ICO-Eintrag nicht quadratisch/RGBA');

// Android
const andRes = res('android/app/src/main/res');
for (const [d, k] of Object.entries({ mdpi: 1, hdpi: 1.5, xhdpi: 2, xxhdpi: 3, xxxhdpi: 4 })) {
  for (const n of ['background', 'foreground', 'monochrome']) png(path.join(andRes, `drawable-${d}`, `ic_launcher_${n}.png`), Math.round(108 * k));
  png(path.join(andRes, `mipmap-${d}`, 'ic_launcher.png'), Math.round(48 * k));
}
const xml = fs.readFileSync(path.join(andRes, 'mipmap-anydpi-v26', 'ic_launcher.xml'), 'utf8');
for (const ref of ['ic_launcher_background', 'ic_launcher_foreground', 'ic_launcher_monochrome']) if (!xml.includes(`@drawable/${ref}`)) fail(`ic_launcher.xml ohne ${ref}`);

console.log(`${checked} PNG geprüft, ${ico.length} ICO-Einträge, ${errors} Fehler.`);
process.exit(errors ? 1 : 0);
