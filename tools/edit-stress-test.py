#!/usr/bin/env python3
"""Editing stress test: guards against text corruption.

Opens a paragraph in amaya under Xvfb (with the openbox window manager), performs
15 random edits by keyboard (Delete, BackSpace, select-and-replace, insertion),
saves, quits, and compares the saved paragraph with the expected text computed
independently.  Before the ustrcpy/ustrncpy fix, edits duplicated and scrambled
the text after the edit point.

  sudo apt install xvfb xdotool openbox     # once
  tools/edit-stress-test.py [build-dir] [seed]

Prints OK or MISMATCH (with expected/got text and the list of operations).
"""
import random, subprocess, time, os, re, sys
repo=os.path.abspath(os.path.join(os.path.dirname(__file__),'..'))
build=sys.argv[1] if len(sys.argv)>1 else 'build'
seed=int(sys.argv[2]) if len(sys.argv)>2 else 1
random.seed(seed)
text="Encipher some text and send the corresponding ciphertext to a colleague, by email. What information has to be known to your colleague, for her/him to be able to decipher the ciphertext? What items of that information are really sensitive?"
env=dict(os.environ, DISPLAY=':95', HOME='/tmp/repro_home')
subprocess.run('rm -rf /tmp/repro_home; mkdir -p /tmp/repro_home/.amaya; printf "[amaya]\\nTIP_OF_THE_DAY_STARTUP=no\\n" > /tmp/repro_home/.amaya/thot.rc; pkill Xvfb; pkill openbox; sleep 1',shell=True)
open('/tmp/corrupt.html','w',encoding='utf-8').write("""<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head><meta http-equiv="Content-Type" content="text/html; charset=utf-8" /><title>Corrupt</title></head>
<body>
<p>"""+text+"""</p>
</body>
</html>
""")
subprocess.Popen('Xvfb :95 -screen 0 1280x900x24',shell=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL); time.sleep(2)
subprocess.Popen('openbox',shell=True,env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL); time.sleep(2)
subprocess.Popen('./amaya /tmp/corrupt.html',shell=True,env=env,cwd=os.path.join(repo,build,'amaya'),stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL); time.sleep(15)
def x(*a): subprocess.run(['xdotool',*a],env=env)
words=["file","XY","longer-word","a","éç"]
ops=[]
for k in range(15):
    pos=random.randint(0,40); kind=random.choice(["del","bs","sel","ins"]); n=random.randint(1,8); w=random.choice(words)
    x('mousemove','60','148','click','1'); time.sleep(0.4); x('key','Home'); time.sleep(0.2)
    for i in range(pos): x('key','Right')
    time.sleep(0.2)
    if kind=="del":
        n=min(n,len(text)-pos)
        for i in range(n): x('key','Delete'); time.sleep(0.05)
        text=text[:pos]+text[pos+n:]
    elif kind=="bs":
        n=min(n,pos)
        for i in range(n): x('key','BackSpace'); time.sleep(0.05)
        text=text[:pos-n]+text[pos:]
    elif kind=="sel":
        n=min(n,len(text)-pos)
        for i in range(n): x('key','shift+Right'); time.sleep(0.05)
        x('type','--delay','80',w); text=text[:pos]+w+text[pos+n:]
    else:
        x('type','--delay','80',w); text=text[:pos]+w+text[pos:]
    ops.append((kind,pos,n,w)); time.sleep(0.4)
x('key','ctrl+s'); time.sleep(2); x('key','ctrl+q'); time.sleep(3)
subprocess.run('pkill amaya; pkill openbox; pkill Xvfb',shell=True)
saved=re.sub(r'\s+',' ',open('/tmp/corrupt.html',encoding='utf-8').read())
got=re.search(r'<p>(.*?)</p>',saved).group(1)
print("OK" if got==text else "MISMATCH")
if got!=text: print(" expected:",text); print(" got:     ",got); print(" ops:",ops)
