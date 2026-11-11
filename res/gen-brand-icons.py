#!/usr/bin/env python3
"""SkyyDesk ikon setini tek bir ustadan uretir.

    python res/gen-brand-icons.py <mark.png>

<mark.png>: logonun yalniz isaret kismi (bulut+ekran), seffaf zeminli, kare
degil - kirpilmis halde. Yazi (SKYDESK) ikona girmez; 16 pikselde okunmuyor.

NEDEN BEYAZ ZEMIN: isaretin yarisi lacivert. Seffaf birakilinca koyu bir
masaustunde ya da koyu gorev cubugunda o yari kayboluyor — olcup goruldu.
Kendi acik zemini olunca her arka planda ayni okunuyor. Android'in uyarlanabilir
ikonu zaten ayri bir zemin katmani istiyor (ic_launcher_background = #ffffff).

Bildirim ikonu (ic_stat_logo) Android tarafindan siluete cevrilir; oraya iki
renkli isaret konursa dolu bir leke cikar. O yuzden alfadan beyaz maske uretilir.
"""
from PIL import Image, ImageDraw
import base64, io, os, struct, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MARK = Image.open(sys.argv[1]).convert("RGBA")
PLATE_BG = (255, 255, 255, 255)


def fit(size, pad, bg=None, radius=None):
    """Isareti kare tuvale oturt. bg=None -> seffaf. radius: kose yuvarlama orani."""
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    if bg:
        plate = Image.new("RGBA", (size, size), bg)
        if radius:
            mask = Image.new("L", (size * 4, size * 4), 0)
            ImageDraw.Draw(mask).rounded_rectangle(
                [0, 0, size * 4 - 1, size * 4 - 1], radius=int(size * 4 * radius), fill=255)
            plate.putalpha(mask.resize((size, size), Image.LANCZOS))
        canvas.alpha_composite(plate)
    inner = int(size * (1 - 2 * pad))
    w, h = MARK.size
    s = min(inner / w, inner / h)
    m = MARK.resize((max(1, round(w * s)), max(1, round(h * s))), Image.LANCZOS)
    canvas.alpha_composite(m, ((size - m.width) // 2, (size - m.height) // 2))
    return canvas


def plate(size):
    """Masaustu / launcher ikonu. Kucuk boyutlarda dolgu ve kose yuvarlamasi
    isaretten piksel caliyor: 16'da %16 dolgu + yuvarlama geriye 11 piksel
    birakiyor ve sekil taninmaz oluyor. Kucukte tuvali doldur."""
    if size <= 24:
        return fit(size, 0.04, PLATE_BG, None)
    if size <= 48:
        return fit(size, 0.09, PLATE_BG, 0.12)
    return fit(size, 0.16, PLATE_BG, 0.20)
def square(size):       return fit(size, 0.16, PLATE_BG, None)   # iOS: opak kare
def bare(size, pad=0.21): return fit(size, pad)                  # seffaf on plan


def circle(size):
    im = fit(size, 0.16, PLATE_BG, None)
    mask = Image.new("L", (size * 4, size * 4), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, size * 4 - 1, size * 4 - 1], fill=255)
    im.putalpha(mask.resize((size, size), Image.LANCZOS))
    return im


def mono(size):
    """Bildirim ikonu: yalniz siluet, beyaz."""
    m = bare(size, 0.12)
    a = m.split()[3]
    out = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    out.putalpha(a)
    return out


def save(im, rel):
    p = os.path.join(ROOT, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    im.save(p)
    return rel


def ico(rel, sizes=(16, 24, 32, 48, 64, 128, 256)):
    p = os.path.join(ROOT, rel)
    plate(256).save(p, format="ICO", sizes=[(s, s) for s in sizes])
    return rel


def icns(rel):
    """icns kabini elle yaz: 'icns' + boyut, sonra tipli PNG parcalari."""
    types = {b"ic07": 128, b"ic08": 256, b"ic09": 512, b"ic10": 1024,
             b"ic11": 32, b"ic12": 64, b"ic13": 256, b"ic14": 512}
    chunks = b""
    for t, s in types.items():
        buf = io.BytesIO()
        plate(s).save(buf, format="PNG")
        d = buf.getvalue()
        chunks += t + struct.pack(">I", len(d) + 8) + d
    p = os.path.join(ROOT, rel)
    with open(p, "wb") as f:
        f.write(b"icns" + struct.pack(">I", len(chunks) + 8) + chunks)
    return rel


written = []

for s in (16, 24, 32, 48, 64, 72, 96, 128, 192, 256, 512):
    written.append(save(plate(s), f"res/icons/{s}.png"))
written += [
    save(plate(512), "res/icon.png"),
    save(plate(1024), "res/mac-icon.png"),
    save(plate(512), "flutter/assets/icon.png"),
    save(plate(256), "fastlane/metadata/android/en-US/images/icon.png"),
    ico("res/icon.ico"),
    ico("res/tray-icon.ico", (16, 24, 32, 48, 64)),
    ico("flutter/windows/runner/resources/app_icon.ico"),
    icns("flutter/macos/Runner/AppIcon.icns"),
]

# Android
for dens, launcher, fg, stat in (("mdpi", 48, 108, 24), ("hdpi", 72, 162, 36),
                                 ("xhdpi", 96, 216, 48), ("xxhdpi", 144, 324, 72),
                                 ("xxxhdpi", 192, 432, 96)):
    b = f"flutter/android/app/src/main/res/mipmap-{dens}"
    written += [
        save(plate(launcher), f"{b}/ic_launcher.png"),
        save(circle(launcher), f"{b}/ic_launcher_round.png"),
        save(bare(fg), f"{b}/ic_launcher_foreground.png"),
        save(mono(stat), f"{b}/ic_stat_logo.png"),
    ]

# iOS: alfa yok, kare
for name, size in (("20x20@1x", 20), ("20x20@2x", 40), ("20x20@3x", 60),
                   ("29x29@1x", 29), ("29x29@2x", 58), ("29x29@3x", 87),
                   ("40x40@1x", 40), ("40x40@2x", 80), ("40x40@3x", 120),
                   ("60x60@2x", 120), ("60x60@3x", 180),
                   ("76x76@1x", 76), ("76x76@2x", 152),
                   ("83.5x83.5@2x", 167), ("1024x1024@1x", 1024)):
    written.append(save(square(size).convert("RGB"),
                        f"flutter/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-{name}.png"))

# icon.svg yalnizca icon.png yuklenemezse devreye giren yedek. Vektor asil
# elimizde olmadigi icin PNG'yi gomuyoruz — eski markayi tasimasin diye.
buf = io.BytesIO()
plate(256).save(buf, format="PNG")
b64 = base64.b64encode(buf.getvalue()).decode()
svg = ('<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
       'viewBox="0 0 256 256" width="256" height="256">'
       f'<image width="256" height="256" xlink:href="data:image/png;base64,{b64}"/></svg>')
with open(os.path.join(ROOT, "flutter/assets/icon.svg"), "w", encoding="utf-8") as f:
    f.write(svg)
written.append("flutter/assets/icon.svg")

print(f"{len(written)} dosya yazildi")
