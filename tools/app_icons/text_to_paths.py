#!/usr/bin/env python3
"""Einmalig: Schriftzug "DartLab" (Inter ExtraBold, OFL) als SVG-Pfade.

Aufruf: python3 text_to_paths.py Inter-ExtraBold.otf positions.json
positions.json: {"o": [[x, y], ...]} Ursprung jedes Zeichens (aus dem Browser,
inkl. Kerning und Zeichenabstand). Ausgabe: JSON mit den Pfaden "Dart" und "Lab".
Benötigt fontTools (nur für dieses Einmalskript, nicht für die Icon-Erzeugung).
"""
import json, sys
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen

font = TTFont(sys.argv[1])
pos = json.load(open(sys.argv[2]))['o']
text = 'DartLab'
SIZE = 190.0
gs = font.getGlyphSet()
cmap = font.getBestCmap()
k = SIZE / font['head'].unitsPerEm

def build(a, b):
    pen = SVGPathPen(gs, ntos=lambda v: ('%.2f' % v).rstrip('0').rstrip('.'))
    for i in range(a, b):
        name = cmap[ord(text[i])]
        x, y = pos[i]
        gs[name].draw(TransformPen(pen, (k, 0, 0, -k, x, y)))
    return pen.getCommands()

print(json.dumps({'dart': build(0, 4), 'lab': build(4, 7)}))
