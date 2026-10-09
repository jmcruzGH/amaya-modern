#!/usr/bin/env python3
"""Copy the cookies that Firefox holds for ONE site into a Netscape-format
cookie file, for Amaya's File > Load cookies... (or for curl / wget).

    firefox-cookies.py sigarra.up.pt -o ~/sigarra-cookies.txt

Typical use: log in to a site with Firefox (which runs the JavaScript that
many login pages need), then load the site's cookies in Amaya to browse and
edit its pages there.

SECURITY WARNING -- read before use
  * The output file contains LOGIN CREDENTIALS: whoever has it can act as
    you on that site until the session ends.  It is created readable by you
    only (mode 0600); delete it as soon as Amaya has loaded it (Amaya offers
    to do so).
  * Only cookies for the site you name (and its parent domains, e.g. up.pt
    for sigarra.up.pt) are copied.  There is deliberately no "all sites"
    option: give Amaya only the sessions you need.
  * This script only reads Firefox's files (from copies); it never changes
    them, and it sends nothing anywhere.
  * Any program running under your account can read Firefox's cookies, as
    this script does; it adds no new access, but it makes the copy easy.
    Use it on your own computer only.

Sources read, in the Firefox profile:
  cookies.sqlite                         persistent cookies
  sessionstore-backups/recovery.jsonlz4  session cookies of the running
                                         Firefox (login cookies are often
                                         session cookies)

Profiles are looked for in the snap (Ubuntu's default), classic and flatpak
locations; the default profile is used unless --profile is given.
"""
import argparse, configparser, json, os, shutil, sqlite3, struct, sys, tempfile, time

PROFILE_ROOTS = [
    '~/snap/firefox/common/.mozilla/firefox',
    '~/.mozilla/firefox',
    '~/.var/app/org.mozilla.firefox/.mozilla/firefox',
]


def die(msg):
    sys.exit('firefox-cookies: ' + msg)


# ---------------------------------------------------------------- profiles
def find_profiles():
    """Return [(path, is_default)] for every profile found."""
    found = []
    for root in PROFILE_ROOTS:
        root = os.path.expanduser(root)
        ini = os.path.join(root, 'profiles.ini')
        if not os.path.isfile(ini):
            continue
        cp = configparser.ConfigParser(interpolation=None)
        cp.read(ini)
        install_default = None
        for sec in cp.sections():
            if sec.startswith('Install') and cp.has_option(sec, 'Default'):
                install_default = cp.get(sec, 'Default')
        for sec in cp.sections():
            if not sec.startswith('Profile') or not cp.has_option(sec, 'Path'):
                continue
            rel = cp.get(sec, 'Path')
            path = os.path.join(root, rel) if cp.get(sec, 'IsRelative', fallback='1') == '1' else rel
            default = (rel == install_default) if install_default else cp.get(sec, 'Default', fallback='0') == '1'
            found.append((path, default))
    return found


def choose_profile(arg):
    if arg:
        p = os.path.expanduser(arg)
        if not os.path.isdir(p):
            die('no such profile folder: %s' % p)
        return p
    profiles = [p for p in find_profiles() if os.path.isdir(p[0])]
    if not profiles:
        die('no Firefox profile found (use --profile)')
    defaults = [p for p, d in profiles if d]
    if defaults:
        return defaults[0]
    if len(profiles) == 1:
        return profiles[0][0]
    die('several profiles and no default; choose one with --profile:\n  ' +
        '\n  '.join(p for p, _ in profiles))


# ---------------------------------------------------------------- matching
def matches(host, site):
    """True if a cookie for host is sent to site (host may be a domain
    cookie such as .up.pt)."""
    h = host.lower().lstrip('.')
    s = site.lower().lstrip('.')
    if s == h or s.endswith('.' + h) and host.startswith('.'):
        return True
    # a cookie for a subdomain of the site (e.g. www.site for site)
    return h.endswith('.' + s)


# ---------------------------------------------------------------- readers
def read_sqlite(profile, site, tmp):
    db = os.path.join(profile, 'cookies.sqlite')
    if not os.path.isfile(db):
        return []
    # Firefox keeps the database locked and recent changes in the -wal file:
    # read a private copy of both
    for suffix in ('', '-wal', '-shm'):
        if os.path.isfile(db + suffix):
            shutil.copy2(db + suffix, os.path.join(tmp, 'cookies.sqlite' + suffix))
    con = sqlite3.connect(os.path.join(tmp, 'cookies.sqlite'))
    cols = {r[1] for r in con.execute('PRAGMA table_info(moz_cookies)')}
    oa = 'originAttributes' if 'originAttributes' in cols else "''"
    rows = con.execute('SELECT host, path, isSecure, expiry, name, value, isHttpOnly, %s '
                       'FROM moz_cookies' % oa).fetchall()
    con.close()
    now = time.time()
    out = []
    for host, path, secure, expiry, name, value, httponly, origin in rows:
        if origin:            # container tabs, partitioned (third-party) cookies
            continue
        if expiry and expiry > 100000000000:   # milliseconds in recent Firefox
            expiry //= 1000
        if expiry and expiry < now:
            continue
        if matches(host, site):
            out.append((host, path, bool(secure), int(expiry or 0), name, value, bool(httponly)))
    return out


def lz4_block_decompress(src, size):
    """Minimal LZ4 block decompressor (mozLz4 files hold one LZ4 block)."""
    dst = bytearray()
    i, n = 0, len(src)
    while i < n:
        token = src[i]; i += 1
        lit = token >> 4
        if lit == 15:
            while True:
                b = src[i]; i += 1
                lit += b
                if b != 255:
                    break
        dst += src[i:i + lit]; i += lit
        if i >= n:
            break
        off = src[i] | (src[i + 1] << 8); i += 2
        if off == 0:
            raise ValueError('bad LZ4 offset')
        ml = token & 15
        if ml == 15:
            while True:
                b = src[i]; i += 1
                ml += b
                if b != 255:
                    break
        ml += 4
        start = len(dst) - off
        if start < 0:
            raise ValueError('bad LZ4 offset')
        for k in range(ml):          # byte by byte: the copy may overlap
            dst.append(dst[start + k])
    if len(dst) != size:
        raise ValueError('bad LZ4 size')
    return bytes(dst)


def read_session(profile, site):
    out = []
    for name in ('sessionstore-backups/recovery.jsonlz4', 'sessionstore.jsonlz4'):
        f = os.path.join(profile, name)
        if not os.path.isfile(f):
            continue
        data = open(f, 'rb').read()
        if data[:8] != b'mozLz40\0':
            continue
        try:
            size = struct.unpack('<I', data[8:12])[0]
            session = json.loads(lz4_block_decompress(data[12:], size))
        except (ValueError, IndexError) as e:
            print('firefox-cookies: cannot read %s (%s)' % (name, e), file=sys.stderr)
            continue
        for c in session.get('cookies', []):
            if c.get('originAttributes') and any(v for v in c['originAttributes'].values()):
                continue
            host = c.get('host', '')
            if matches(host, site):
                out.append((host, c.get('path', '/'), bool(c.get('secure')), 0,
                            c.get('name', ''), c.get('value', ''), bool(c.get('httponly'))))
        break              # recovery.jsonlz4 is the current one when present
    return out


# ---------------------------------------------------------------- output
def netscape_line(c):
    host, path, secure, expiry, name, value, httponly = c
    domain = ('#HttpOnly_' if httponly else '') + host
    return '\t'.join([domain, 'TRUE' if host.startswith('.') else 'FALSE', path or '/',
                      'TRUE' if secure else 'FALSE', str(expiry), name, value])


def main():
    ap = argparse.ArgumentParser(
        description='Copy the Firefox cookies of ONE site into a Netscape cookie file '
                    '(for Amaya: File > Load cookies...). The output contains login '
                    'credentials: delete it after use.')
    ap.add_argument('site', nargs='?', help='site name, e.g. sigarra.up.pt')
    ap.add_argument('-o', '--output', help='output file (created with mode 0600); default: standard output')
    ap.add_argument('--profile', help='Firefox profile folder (default: the default profile)')
    ap.add_argument('--list-profiles', action='store_true', help='list the profiles found and exit')
    args = ap.parse_args()

    if args.list_profiles:
        for p, d in find_profiles():
            print(('* ' if d else '  ') + p)
        return
    if not args.site:
        ap.error('give the site name, e.g. sigarra.up.pt')
    site = args.site.strip().lower()
    if '://' in site:
        site = site.split('://', 1)[1]
    site = site.split('/', 1)[0].split(':', 1)[0]
    if '.' not in site.strip('.'):
        die('give a full site name, e.g. sigarra.up.pt (not "%s")' % args.site)

    profile = choose_profile(args.profile)
    tmp = tempfile.mkdtemp(prefix='ffcookies-')
    try:
        cookies = read_sqlite(profile, site, tmp) + read_session(profile, site)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    # one cookie per (host, path, name): the session store is the most recent
    unique = {}
    for c in cookies:
        unique[(c[0], c[1], c[4])] = c
    cookies = list(unique.values())

    text = ('# Netscape HTTP Cookie File\n'
            '# Firefox cookies for %s -- CONTAINS LOGIN CREDENTIALS: delete after use\n'
            % site) + ''.join(netscape_line(c) + '\n' for c in cookies)
    if args.output:
        fd = os.open(os.path.expanduser(args.output), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, 'w') as f:
            f.write(text)
    else:
        sys.stdout.write(text)
    hosts = sorted({c[0].lstrip('.') for c in cookies})
    print('firefox-cookies: %d cookie(s) for %s%s' % (len(cookies), site,
          (' (' + ', '.join(hosts) + ')') if hosts else
          ' -- none found: are you logged in with Firefox?'), file=sys.stderr)


if __name__ == '__main__':
    main()
