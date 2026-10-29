// DartLab / DartLab Lite: Icon-Zeichnung als SVG-Text (1024er Raster).
//
// Eigene Zeichnung, keine Marken Dritter. Das Motiv: drei verdrehte Zielbögen
// im Verlauf Koralle, Magenta, Violett um einen hellen Punkt (DartLab auf
// dunkler Violettplatte), bei Lite auf Türkis-Blau-Platte mit weißen Bögen und
// einem Auge-Abzeichen für "nur ansehen".
//
// Die Zeichnung wird je nach Größe vereinfacht (Detailstufe): ab 150 px mit
// Glühen, 44 bis 149 px ohne Glühen, darunter zwei kräftige Bögen. Der
// Schriftzug "DartLab" erscheint nur bei DartLab und nur, wenn er lesbar bleibt
// (siehe TEXT_MIN_PX).
import { TEXT_DART, TEXT_LAB } from './text_paths.mjs';

/** Ab dieser effektiven Symbolgröße (px) wird der Schriftzug gezeichnet. */
export const TEXT_MIN_PX = 100;

const f = (n) => +n.toFixed(2);
const rad = (a) => (a * Math.PI) / 180;
const pt = (cx, cy, r, a) => [f(cx + r * Math.sin(rad(a))), f(cy - r * Math.cos(rad(a)))];
const arc = (cx, cy, r, a0, a1) => {
  const [x0, y0] = pt(cx, cy, r, a0);
  const [x1, y1] = pt(cx, cy, r, a1);
  return `M${x0} ${y0}A${r} ${r} 0 ${a1 - a0 > 180 ? 1 : 0} 1 ${x1} ${y1}`;
};
const stops = (cols) => cols.map((c, i) => `<stop offset="${f(i / (cols.length - 1))}" stop-color="${c}"/>`).join('');

// Platten: Grundverlauf plus zwei weiche Lichtflecken [x, y, r, Farbe, Deckkraft].
const PLATE = {
  dark: { base: ['#1E1236', '#07040F'], glows: [[240, 190, 640, '#8A3CFF', 0.5], [850, 880, 560, '#FF5A4F', 0.3]] },
  lite: { base: ['#3BE6CF', '#1B7BE2'], glows: [[240, 170, 620, '#FFFFFF', 0.38], [860, 890, 520, '#1B3FD8', 0.38]] },
};

const levelFor = (px) => (px >= 150 ? 2 : px >= 44 ? 1 : 0);

function badge(cx, cy, r) {
  return `<g transform="translate(${cx} ${cy})"><circle r="${r * 1.08}" fill="#000" opacity=".25" transform="translate(0 ${r * 0.08})"/><circle r="${r}" fill="#0A1B4D"/><circle r="${r * 0.92}" fill="none" stroke="#fff" stroke-opacity=".35" stroke-width="${f(r * 0.06)}"/><path d="M${-r * 0.68} 0Q0 ${-r * 0.92} ${r * 0.68} 0Q0 ${r * 0.92} ${-r * 0.68} 0Z" fill="#fff"/><circle r="${r * 0.3}" fill="#1F6BEB"/><circle r="${r * 0.14}" fill="#06102A"/></g>`;
}

// Zielbögen. mono: einfarbig (Themed-Icon), ohne Glühen.
function arcsArt(lite, level, mono) {
  const cols = lite ? ['#FFFFFF', '#E2FFF8', '#9CF3E4'] : ['#FF7A59', '#EA3A9C', '#7F4EFF'];
  const dotColor = mono ? '#000' : lite ? '#0A2F6A' : '#FFFFFF';
  const paint = mono ? '#000' : 'url(#dg)';
  const defs = mono ? '' : `<linearGradient id="dg" gradientUnits="userSpaceOnUse" x1="180" y1="180" x2="860" y2="860">${stops(cols)}</linearGradient>`;
  const arcs = level === 0
    ? [[368, 124, 30, 330], [237, 124, 120, 420]]
    : [[340, 80, 35, 325], [232, 80, 125, 415], [124, 80, 215, 505]];
  const dotR = level === 0 ? 118 : 46;
  const strokes = () => arcs.map(([r, w, a0, a1]) => `<path d="${arc(512, 512, r, a0, a1)}" fill="none" stroke="${paint}" stroke-width="${w}" stroke-linecap="round"/>`).join('');
  let svg = '';
  if (level === 2 && !mono) {
    svg += `<g filter="url(#gl)" opacity="${lite ? 0.35 : 0.6}">${strokes()}</g>`;
    svg += `<circle cx="512" cy="512" r="${dotR * 1.6}" fill="${lite ? '#fff' : '#FF7A59'}" opacity=".5" filter="url(#gl2)"/>`;
  }
  svg += strokes() + `<circle cx="512" cy="512" r="${dotR}" fill="${dotColor}"/>`;
  return { svg, defs, extent: level === 0 ? 432 : 382 };
}

// Bögen kleiner und nach oben, darunter der Schriftzug (Variante "unten").
function arcsWithText(level) {
  const a = arcsArt(false, level, false);
  const s = 0.66, cy = 400;
  const defs = a.defs + `<linearGradient id="tg" gradientUnits="userSpaceOnUse" x1="520" y1="700" x2="900" y2="880"><stop offset="0" stop-color="#FF7A59"/><stop offset=".55" stop-color="#EA3A9C"/><stop offset="1" stop-color="#8A55FF"/></linearGradient>`;
  const svg = `<g transform="translate(512 ${cy}) scale(${s}) translate(-512 -512)">${a.svg}</g>`
    + `<path d="${TEXT_DART}" fill="#FFFFFF"/><path d="${TEXT_LAB}" fill="url(#tg)"/>`;
  return { svg, defs, extent: 540 };
}

function plateDefs(lite) {
  const pl = PLATE[lite ? 'lite' : 'dark'];
  let d = `<linearGradient id="pl" x1="0" y1="0" x2="1" y2="1">${stops(pl.base)}</linearGradient>`;
  pl.glows.forEach(([x, y, r, c, o], i) => {
    d += `<radialGradient id="pg${i}" gradientUnits="userSpaceOnUse" cx="${x}" cy="${y}" r="${r}"><stop offset="0" stop-color="${c}" stop-opacity="${o}"/><stop offset="1" stop-color="${c}" stop-opacity="0"/></radialGradient>`;
  });
  d += `<linearGradient id="gloss" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity="${lite ? 0.22 : 0.1}"/><stop offset=".5" stop-color="#fff" stop-opacity="0"/></linearGradient>`;
  d += `<filter id="sh" x="-20%" y="-20%" width="140%" height="150%"><feDropShadow dx="0" dy="14" stdDeviation="16" flood-color="#000" flood-opacity=".5"/></filter>`;
  d += `<filter id="gl" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="22"/></filter><filter id="gl2" x="-60%" y="-60%" width="220%" height="220%"><feGaussianBlur stdDeviation="34"/></filter>`;
  return d;
}
const plateFill = (lite, shape) => {
  const pl = PLATE[lite ? 'lite' : 'dark'];
  return shape('url(#pl)') + pl.glows.map((_, i) => shape(`url(#pg${i})`)).join('') + shape('url(#gloss)');
};
const rect = (x, y, w, rx) => (fill) => `<rect x="${x}" y="${y}" width="${w}" height="${w}" rx="${rx}" fill="${fill}"/>`;
const wrap = (size, inner) => `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 1024 1024">${inner}</svg>`;

/**
 * SVG-Text eines Icons.
 *  lite: DartLab Lite (Türkis-Blau, Auge-Abzeichen, nie mit Schriftzug)
 *  fmt:  'ios'    randlos, volles Quadrat (iOS rundet selbst)
 *        'mac'    abgerundetes Quadrat 824 von 1024 mit Rand und Schatten
 *        'win'    abgerundetes Quadrat, füllt die Fläche (Windows)
 *        'legacy' abgerundetes Quadrat für Android vor 8
 *        'andBg' / 'andFg' / 'mono'  adaptive Ebenen (108 dp), Themed-Icon
 *  size: Zielgröße in px (bestimmt Detailstufe und Schriftzug)
 *  text: true/false erzwingt/verbietet den Schriftzug, sonst nach TEXT_MIN_PX
 */
export function iconSvg({ lite = false, fmt, size, text }) {
  const eff = fmt === 'mac' ? size * 0.8 : size;
  const wantText = !lite && !['andBg', 'andFg', 'mono', 'legacy'].includes(fmt) && (text ?? eff >= TEXT_MIN_PX);
  const level = levelFor(fmt === 'andFg' || fmt === 'mono' ? size * 0.6 : eff);
  const art = wantText ? arcsWithText(levelFor(eff * 0.62)) : arcsArt(lite, level, fmt === 'mono');
  const withBadge = lite && fmt !== 'mono' && fmt !== 'andBg' && (fmt === 'andFg' ? size * 0.667 : eff) >= 44;
  const grow = fmt === 'win' || fmt === 'legacy' ? (size <= 32 ? 1.08 : 1.02) : 1;
  const defs = `<defs>${plateDefs(lite)}${art.defs}</defs>`;
  const body = `<g transform="translate(512 512) scale(${grow}) translate(-512 -512)">${art.svg}</g>`;
  const bd = withBadge ? badge(745, 745, 118) : '';

  if (fmt === 'ios' || fmt === 'andBg') return wrap(size, defs + plateFill(lite, rect(0, 0, 1024, 0)) + (fmt === 'andBg' ? '' : body + bd));
  if (fmt === 'win' || fmt === 'legacy') return wrap(size, defs + plateFill(lite, rect(0, 0, 1024, fmt === 'win' ? 200 : 230)) + body + bd);
  if (fmt === 'mac') {
    const k = 824 / 1024;
    const clip = '<clipPath id="pc"><rect x="100" y="100" width="824" height="824" rx="185"/></clipPath>';
    const shadow = '<g filter="url(#sh)"><rect x="100" y="100" width="824" height="824" rx="185" fill="#000"/></g>';
    const edge = `<rect x="101.5" y="101.5" width="821" height="821" rx="183.5" fill="none" stroke="#fff" stroke-opacity="${lite ? 0.35 : 0.2}" stroke-width="3"/>`;
    return wrap(size, defs.replace('</defs>', clip + '</defs>') + shadow + `<g clip-path="url(#pc)">${plateFill(lite, rect(100, 100, 824, 185))}</g>` + edge
      + `<g transform="translate(512 512) scale(${k}) translate(-512 -512)">${body}${bd}</g>`);
  }
  if (fmt === 'andFg' || fmt === 'mono') {
    // Alles im 66-dp-Kreis der Safe-Zone (66 von 108 dp), Abzeichen eingerechnet.
    const k = (0.611 * 512 * 0.985) / Math.max(art.extent, 428);
    return wrap(size, defs + `<g transform="translate(512 512) scale(${f(k)}) translate(-512 -512)">${body}${bd}</g>`);
  }
  throw new Error(`Unbekanntes Format: ${fmt}`);
}
