// Dynamic brand SVG only draws the icon so Flutter can render Chinese text reliably on web.

import 'package:flutter/material.dart';

String buildAppBrandIconSvg(Color accent) {
  final light = Color.lerp(accent, Colors.white, 0.32) ?? accent;
  final dark = Color.lerp(accent, const Color(0xff1d4ed8), 0.4) ?? accent;
  final soft = Color.lerp(accent, Colors.white, 0.7) ?? accent;

  return '''
<svg width="72" height="52" viewBox="0 0 72 52" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="g1" x1="2" y1="1" x2="66" y2="49">
      <stop offset="0%" stop-color="${_hex(light)}"/>
      <stop offset="100%" stop-color="${_hex(dark)}"/>
    </linearGradient>
  </defs>
  <path d="M42 44H18C8.6 44 2 37.6 2 29.5C2 22 7.8 15.8 15.3 15.1C18.2 6.5 26.4 1 36 1C47.4 1 56.7 9.4 57.8 20.3C65 21.6 70 27.1 70 34C70 39.7 65.2 44 59 44H52" fill="url(#g1)"/>
  <path d="M26 31H54C59 31 63 35 63 40C63 45 59 49 54 49H26C21 49 17 45 17 40C17 35 21 31 26 31Z" fill="#FFFFFF" opacity="0.95"/>
  <circle cx="54" cy="40" r="5" fill="${_hex(dark)}"/>
  <path d="M26 36H47" stroke="${_hex(dark)}" stroke-width="3" stroke-linecap="round"/>
  <path d="M26 44H42" stroke="${_hex(soft)}" stroke-width="3" stroke-linecap="round"/>
</svg>
''';
}

String _hex(Color color) {
  final value = color.toARGB32() & 0x00ffffff;
  return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}
