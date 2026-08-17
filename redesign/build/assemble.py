#!/usr/bin/env python3
"""Assemble a standalone page: head.tmpl + <main> body + foot.tmpl, with the
active nav marked and the Gloock font embedded. Page body files may start with
their own <style> block (valid inside <main>, applies globally)."""
import sys, os
BUILD = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(BUILD)

def main():
    if len(sys.argv) < 6:
        print("usage: assemble.py <out> <active> <title> <desc> <bodyfile>")
        sys.exit(1)
    out, active, title, desc, bodyfile = sys.argv[1:6]
    head = open(os.path.join(BUILD, "head.tmpl")).read()
    foot = open(os.path.join(BUILD, "foot.tmpl")).read()
    body = open(bodyfile).read()
    b64 = open(os.path.join(ROOT, "assets", "gloock.b64")).read().strip()

    nav = {"home":"__A_HOME__","about":"__A_ABOUT__","services":"__A_SERVICES__",
           "pay":"__A_PAY__","contact":"__A_CONTACT__"}
    for key, tok in nav.items():
        head = head.replace(tok, 'aria-current="page"' if key == active else '')

    head = head.replace("__TITLE__", title).replace("__DESC__", desc)
    head = head.replace("__PAGECSS__", "")
    html = head + "\n" + body + "\n" + foot
    html = html.replace("__GLOOCK_B64__", b64)

    # integrity checks
    assert "__GLOOCK_B64__" not in html, "font placeholder left"
    for leftover in ["__A_HOME__","__A_ABOUT__","__A_SERVICES__","__A_PAY__","__A_CONTACT__","__TITLE__","__DESC__","__PAGECSS__"]:
        assert leftover not in html, f"leftover token {leftover}"
    open(out, "w").write(html)
    print(f"built {out}  ({round(len(html)/1024,1)} KB)")

if __name__ == "__main__":
    main()
