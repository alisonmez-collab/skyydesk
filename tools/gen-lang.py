# -*- coding: utf-8 -*-
"""Yeni dil dosyalarini uretir.

RustDesk'te bos deger Ingilizce'ye duser (src/lang.rs, translate_locale).
Bu yuzden bir dili tam cevirmeden de eklemek mumkun: kullanicinin en cok
gordugu metinler cevrilir, gerisi Ingilizce kalir. Hic olmamasindan iyidir
ve dosya buyudukce doldurulabilir.

Anahtar kumesi tr.rs'ten alinir — depodaki en dolu dosya odur.
"""
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
LANGDIR = os.path.join(ROOT, 'src', 'lang')

HEADER = """lazy_static::lazy_static! {
pub static ref T: std::collections::HashMap<&'static str, &'static str> =
    [
"""
FOOTER = """    ].iter().cloned().collect();
}
"""


def keys_from(path):
    s = io.open(path, encoding='utf-8').read()
    return re.findall(r'^        \("((?:[^"\\]|\\.)*)", ', s, re.M)


def write_lang(code, table):
    keys = keys_from(os.path.join(LANGDIR, 'tr.rs'))
    out = [HEADER]
    for k in keys:
        v = table.get(k, '')
        out.append('        ("%s", "%s"),\n' % (k, v.replace('"', '\\"')))
    out.append(FOOTER)
    p = os.path.join(LANGDIR, '%s.rs' % code)
    io.open(p, 'w', encoding='utf-8', newline='\n').write(''.join(out))
    return len(keys), sum(1 for k in keys if table.get(k))


if __name__ == '__main__':
    from lang_tables import TABLES
    for code, table in sorted(TABLES.items()):
        total, filled = write_lang(code, table)
        print('%-3s %d anahtar, %d cevrili (%d Ingilizce\'ye duser)'
              % (code, total, filled, total - filled))
