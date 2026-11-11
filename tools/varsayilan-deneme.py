#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Varsayilani kapali yetkiler iki tarafta AYNI mi?

Kural iki dilde yazili: Rust izni uyguluyor, Dart ayar kutusunu ciziyor.
Ayrisirlarsa kutu "acik" gorunurken izin kapali kalir -- kullanicinin gordugu
ile makinenin yaptigi ayrisir. Tek dosyada birlesemedikleri icin esitlikleri
burada olculuyor.

Kullanim:  python3 tools/varsayilan-deneme.py
"""
import io
import os
import re
import sys

KOK = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Rust: const VARSAYILAN_KAPALI: &[&str] = &[keys::OPTION_ENABLE_CAMERA, ...];
rs = io.open(os.path.join(KOK, "libs/hbb_common/src/config.rs"),
             encoding="utf-8").read()
m = re.search(r"const VARSAYILAN_KAPALI:[^=]*=\s*&\[([^\]]*)\]", rs)
if not m:
    print("HATALI  Rust tarafinda VARSAYILAN_KAPALI bulunamadi")
    sys.exit(1)
rust_anahtar = set(re.findall(r"OPTION_([A-Z_]+)", m.group(1)))

# Dart: const List<String> kVarsayilanKapali = [kOptionEnableCamera, ...];
dart = io.open(os.path.join(KOK, "flutter/lib/common.dart"), encoding="utf-8").read()
m = re.search(r"const List<String> kVarsayilanKapali\s*=\s*\[([^\]]*)\]", dart)
if not m:
    print("HATALI  Dart tarafinda kVarsayilanKapali bulunamadi")
    sys.exit(1)


def dart_to_rust(ad):
    # kOptionEnableCamera -> ENABLE_CAMERA
    ad = re.sub(r"^kOption", "", ad.strip())
    return re.sub(r"(?<!^)(?=[A-Z])", "_", ad).upper()


dart_anahtar = {dart_to_rust(a) for a in m.group(1).split(",") if a.strip()}

hata = 0
if rust_anahtar != dart_anahtar:
    print("HATALI  iki taraf ayni listeyi tutmuyor")
    print("        yalniz Rust'ta : %s" % (sorted(rust_anahtar - dart_anahtar) or "-"))
    print("        yalniz Dart'ta : %s" % (sorted(dart_anahtar - rust_anahtar) or "-"))
    hata += 1
else:
    print("TAMAM   varsayilani kapali yetkiler iki tarafta ayni: %s"
          % ", ".join(sorted(rust_anahtar)))

# Bu iki yetki listede DURMALI: sahadan bildirilen kusur buydu.
for zorunlu in ("ENABLE_CAMERA", "ENABLE_BLOCK_INPUT"):
    if zorunlu in rust_anahtar:
        print("TAMAM   %s varsayilan kapali" % zorunlu)
    else:
        print("HATALI  %s listede yok -- varsayilan acik demektir" % zorunlu)
        hata += 1

print("hatali adim: %d" % hata)
sys.exit(1 if hata else 0)
