#!/usr/bin/env python3
# App Store (6.5" iPhone) gorselleri: dikey 1284x2778, yatay 2778x1284.
# magaza-gorselleri.py'nin iOS esi: ayni renkler ve fontlar, ama ham kareler
# onceden hazir (durum cubugu kirpilmis, kisisel alanlar bulaniklastirilmis),
# yatay kare icin metin solda, kare sagda.
import base64, json, pathlib, subprocess, sys, tempfile

FONT = pathlib.Path("/var/www/skydesk/assets/fonts")
RENK = {"zemin": "#002B45", "dip": "#001A2C", "turkuaz": "#3FC9CF", "beyaz": "#FFFFFF"}
LATIN = "U+0000-00FF,U+0131,U+0152-0153,U+02BB-02BC,U+02C6,U+02DA,U+02DC,U+2000-206F,U+20AC,U+2122"
LATIN_EXT = "U+0100-02AF,U+1E00-1EFF,U+20A0-20CF,U+2C60-2C7F,U+A720-A7FF"

def uri(p, t): return f"data:{t};base64," + base64.b64encode(p.read_bytes()).decode()

def fontlar():
    css = ""
    for ad, dosya, w in [("BarlowCondensed", "BarlowCondensed-700", 700),
                         ("Geist", "Geist-500", 500), ("Geist", "Geist-600", 600)]:
        for alt, aralik in [("latin", LATIN), ("latin-ext", LATIN_EXT)]:
            p = FONT / f"{dosya}-{alt}.woff2"
            if p.exists():
                css += (f"@font-face{{font-family:'{ad}';font-weight:{w};font-display:block;"
                        f"src:url({uri(p,'font/woff2')}) format('woff2');unicode-range:{aralik}}}")
    return css

def sayfa(kare, ustyazi, baslik, yatay, G, Y):
    ortak = f"""{fontlar()}
*{{margin:0;padding:0;box-sizing:border-box}}
html,body{{width:{G}px;height:{Y}px;overflow:hidden}}
body{{background:{RENK['zemin']};font-family:Geist,sans-serif;display:flex;position:relative}}
body::before{{content:'';position:absolute;inset:0;
  background:radial-gradient(120% 70% at 12% 0%,#004168 0%,{RENK['zemin']} 58%,{RENK['dip']} 100%)}}
.yazi{{position:relative;flex:0 0 auto}}
.ustyazi{{font-weight:600;letter-spacing:.18em;text-transform:uppercase;color:{RENK['turkuaz']};
  display:flex;align-items:center;gap:24px}}
.ustyazi::after{{content:'';height:3px;flex:1;background:{RENK['turkuaz']};opacity:.35}}
h1{{font-family:BarlowCondensed,sans-serif;font-weight:700;line-height:.96;color:#fff;text-wrap:balance}}
.cerceve{{position:relative;flex:1;display:flex;min-height:0;min-width:0}}
.cerceve img{{display:block;border:2px solid rgba(255,255,255,.14);
  box-shadow:0 -2px 0 rgba(255,255,255,.06),0 50px 110px rgba(0,0,0,.5)}}"""
    if yatay:
        stil = ortak + """
body{flex-direction:row;align-items:center}
.yazi{width:880px;padding:0 40px 0 120px}
.ustyazi{font-size:30px} h1{font-size:120px;margin-top:36px}
.cerceve{justify-content:center;align-items:center;padding:0 110px 0 40px}
.cerceve img{width:100%;height:auto;border-radius:36px}"""
    else:
        stil = ortak + """
body{flex-direction:column}
.yazi{padding:130px 100px 0}
.ustyazi{font-size:32px} h1{font-size:128px;margin-top:38px;max-width:15ch}
.cerceve{justify-content:center;align-items:flex-start;padding:90px 128px 0}
.cerceve img{width:100%;height:auto;border-radius:44px 44px 0 0;border-bottom:0}"""
    return (f'<!doctype html><meta charset="utf-8"><style>{stil}</style>'
            f'<div class="yazi"><div class="ustyazi">{ustyazi}</div><h1>{baslik}</h1></div>'
            f'<div class="cerceve"><img src="{uri(kare,"image/png")}"></div>')

def main():
    liste = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
    ham, cikti = pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3]); cikti.mkdir(parents=True, exist_ok=True)
    for i, k in enumerate(liste, 1):
        kare = ham / k["kare"]
        w, h = map(int, subprocess.run(["identify", "-format", "%w %h", str(kare)], capture_output=True, text=True, check=True).stdout.split())
        yatay = w > h
        G, Y = (2778, 1284) if yatay else (1284, 2778)
        with tempfile.TemporaryDirectory() as t:
            html = pathlib.Path(t) / "s.html"
            html.write_text(sayfa(kare, k["ustyazi"], k["baslik"], yatay, G, Y), encoding="utf-8")
            png = cikti / f"{i}.png"
            subprocess.run(["chromium", "--headless", "--no-sandbox", "--disable-gpu", "--hide-scrollbars",
                            "--force-device-scale-factor=1", f"--window-size={G},{Y}",
                            f"--screenshot={png}", f"file://{html}"], check=True, capture_output=True)
            # App Store alfa kanalli PNG kabul etmiyor
            subprocess.run(["convert", str(png), "-alpha", "off", str(png)], check=True)
        print(i, k["kare"], G, Y)

main()
