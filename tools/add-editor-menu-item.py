#!/usr/bin/env python3
"""Add a menu entry to Amaya's EDITOR application, by hand-editing the
generated files (the schema compilers do not build in this port).

    tools/add-editor-menu-item.py AFTER_LABEL NEW_LABEL ACTION 'English text' \
        [lang='translation' ...]

  AFTER_LABEL  existing button or toggle label after which the entry goes,
               e.g. BPrint or TBold; the new entry is of the same kind
               (the entry goes in the same menu, right after it)
  NEW_LABEL    label of the new entry, e.g. BLoadCookies
  ACTION       C function called by the entry: void ACTION (Document, View)
  text         menu text; '&' marks the mnemonic

Run from the top of the source tree.  It edits:
  amaya/EDITOR.A                 the menu definition (for a future regeneration)
  amaya/generated/EDITOR.h       label numbers (labels after the new one shift)
  amaya/generated/EDITORAPP.c    extern, menu action, menu item, item and
                                 action counts
  config/*-amayadialogue         the label text, with the same renumbering
  config/amaya.profiles          ACTION, next to AFTER_LABEL's action, so that
                                 the entry is shown
"""
import glob, re, sys


def die(msg):
    sys.exit("add-editor-menu-item: " + msg)


def main():
    if len(sys.argv) < 5:
        die("usage: AFTER_LABEL NEW_LABEL ACTION 'text' [lang='text' ...]")
    after, new, action, text = sys.argv[1:5]
    texts = {'en': text}
    for arg in sys.argv[5:]:
        lang, _, t = arg.partition('=')
        texts[lang] = t

    # EDITOR.A
    p = 'amaya/EDITOR.A'
    a = open(p, encoding='latin1').read()
    m = re.search(r'^(\s*)(\S+) (button|toggle):%s\s*->\s*(\w+)\s*;[^\n]*\n' % after, a, re.M)
    if not m:
        die("%s not found in %s" % (after, p))
    if re.search(r'(button|toggle):%s\b' % new, a):
        die("%s already exists" % new)
    menu, kind, after_action = m.group(2), m.group(3), m.group(4)
    letter = 'T' if kind == 'toggle' else 'B'
    a = a[:m.end()] + '%s%s %s:%s -> %s;\n' % (m.group(1), menu, kind, new, action) + a[m.end():]
    open(p, 'w', encoding='latin1').write(a)

    # EDITOR.h: new label right after AFTER_LABEL, later labels shift by one
    p = 'amaya/generated/EDITOR.h'
    h = open(p).read()
    m = re.search(r'^#define %s  (\d+)$' % after, h, re.M)
    if not m:
        die("%s not found in %s" % (after, p))
    num = int(m.group(1)) + 1
    out, inlabels = [], False
    for line in h.split('\n'):
        if line.startswith('/* Beginning of labels */'):
            inlabels = True
        lm = re.match(r'(#define \w+  )(\d+)$', line)
        if inlabels and lm and int(lm.group(2)) >= num:
            line = lm.group(1) + str(int(lm.group(2)) + 1)
        mm = re.match(r'(#define MAX_EDITOR_LABEL\s+)(\d+)$', line)
        if mm:
            line = mm.group(1) + str(int(mm.group(2)) + 1)
        out.append(line)
        if line == '#define %s  %d' % (after, num - 1):
            out.append('#define %s  %d' % (new, num))
    open(p, 'w').write('\n'.join(out))

    # EDITORAPP.c
    p = 'amaya/generated/EDITORAPP.c'
    c = open(p).read()
    def after_line(pattern, addition):
        nonlocal c
        mm = re.search(pattern, c, re.M)
        if not mm:
            die("pattern not found in %s: %s" % (p, pattern))
        end = c.index('\n', mm.end()) + 1
        c = c[:end] + addition + c[end:]
    after_line(r'^extern void %s \(Document document, View view\);' % after_action,
               'extern void %s (Document document, View view);\n' % action)
    after_line(r'^  TteAddMenuAction\("%s", \(Proc\)%s, FALSE\);' % (after_action, after_action),
               '  TteAddMenuAction("%s", (Proc)%s, FALSE);\n' % (action, action))
    mm = re.search(r'^(\s*)TteAddMenuItem \((\w+), (-?\w+), %s, "%s", \'%s\', NULL\);' % (after, after_action, letter), c, re.M)
    if not mm:
        die("menu item %s not found in %s" % (after, p))
    end = c.index('\n', mm.end()) + 1
    c = c[:end] + "%sTteAddMenuItem (%s, %s, %s, \"%s\", '%s', NULL);\n" % (
        mm.group(1), mm.group(2), mm.group(3), new, action, letter) + c[end:]
    if mm.group(3) == '-1':
        c, n = re.subn(r'TteAddMenu \(0, %s, (\d+),' % mm.group(2),
                       lambda x: 'TteAddMenu (0, %s, %d,' % (mm.group(2), int(x.group(1)) + 1), c)
    else:
        c, n = re.subn(r'TteAddSubMenu \(%s, %s, (\d+)\);' % (mm.group(2), mm.group(3)),
                       lambda x: 'TteAddSubMenu (%s, %s, %d);' % (mm.group(2), mm.group(3), int(x.group(1)) + 1), c)
    if n != 1:
        die("item count of menu %s not found" % mm.group(2))
    c, n = re.subn(r'TteInitMenus \(appName, (\d+)\);',
                   lambda x: 'TteInitMenus (appName, %d);' % (int(x.group(1)) + 1), c)
    if n != 1:
        die("TteInitMenus not found")
    open(p, 'w').write(c)

    # label files
    for f in sorted(glob.glob('config/*-amayadialogue')):
        lang = f.split('/')[-1].split('-')[0]
        raw = open(f, 'rb').read()
        enc = 'utf-8' if b'encoding= utf8' in raw.split(b'\n')[0] else 'latin1'
        res, done = [], False
        for line in raw.decode(enc).split('\n'):
            lm = re.match(r'(\d+)( .*|)$', line)
            if lm and int(lm.group(1)) >= num:
                line = str(int(lm.group(1)) + 1) + lm.group(2)
            res.append(line)
            if lm and int(lm.group(1)) == num - 1:
                res.append('%d %s' % (num, texts.get(lang, texts['en'])))
                done = True
        if not done:
            die("label %d not found in %s" % (num - 1, f))
        open(f, 'wb').write('\n'.join(res).encode(enc))

    # profiles
    p = 'config/amaya.profiles'
    pr = open(p, encoding='latin1').read()
    pr, n = re.subn(r'^(&?)%s$' % after_action, lambda x: '%s%s\n%s%s' % (x.group(1), after_action, x.group(1), action),
                    pr, count=1, flags=re.M)
    if n != 1:
        print("note: %s not in %s; add %s there by hand" % (after_action, p, action))
    open(p, 'w', encoding='latin1').write(pr)
    print("%s = %d added after %s in menu %s" % (new, num, after, menu))


if __name__ == '__main__':
    main()
