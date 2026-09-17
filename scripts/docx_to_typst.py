# -*- coding: utf-8 -*-
"""Re-extract مدار منطقی.docx into src/main.typ (optional maintenance helper)."""
from __future__ import annotations

import shutil
import zipfile
import xml.etree.ElementTree as ET
from pathlib import Path

W = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"
A = "{http://schemas.openxmlformats.org/drawingml/2006/main}"
R = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}"
WP = "{http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing}"
V = "{urn:schemas-microsoft-com:vml}"

ROOT = Path(__file__).resolve().parents[1]
EXTRACT = ROOT / "_extract"
SRC = ROOT / "src"
ASSETS = SRC / "assets"
DOCX_MEDIA = EXTRACT / "word" / "media"
LINE_WIDTH_EMU = 6.5 * 914400
HEADING_TITLES = {
    "سیمولیشن",
    "وریلاگ",
    "اعمال کلاک",
    "نحوه ساخت یک ماژول در شماتیک",
}
