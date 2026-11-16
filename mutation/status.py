"""How far a mutation run has got (issue: show a run's progress). Read-only.

  status.py init <work> key=value …   run.sh, at the start: writes <work>/run.info,
                                      the run's own facts and this machine's
  status.py status [<work>]           the full report; with no <work>, the newest
                                      mutation.* under $TMPDIR (else /tmp)
  status.py line <work>               one line, as run.sh prints every few minutes

Everything here is read from the work directory run.sh keeps: list (every mutant:
id, file, suites, expect), res/<id> (a finished mutant: id, verdict, by, why), m/<id>
(a mutant running now), first/<id> (a kill made under load, waiting to be run alone),
phases (each step and when it began) and run.info. Nothing is written but run.info,
by init: a report changes no result, stamp or exit status.
"""
import glob, os, platform, sys, time

TIME_BOUND = ("(bound ", "(want ≤", "want 'bounded'")


def rd(p):
    with open(p, encoding='utf-8', errors='replace') as f:
        return f.read()


def kv(p):
    out = {}
    if os.path.exists(p):
        for line in rd(p).splitlines():
            k, _, v = line.partition('=')
            if k: out[k] = v
    return out


def hm(sec):
    sec = int(max(sec, 0))
    h, m = sec // 3600, (sec % 3600) // 60
    return '%dh %02dm' % (h, m) if h else '%dm' % m if m else '%ds' % sec


def clock(t):
    return time.strftime('%a %d %b %H:%M', time.localtime(t))


def system():
    """This machine, as the report names it."""
    if sys.platform == 'darwin':
        v = platform.mac_ver()[0]
        osname = 'macOS ' + v if v else 'macOS'
    else:
        osname = platform.system()
        try:
            for line in rd('/etc/os-release').splitlines():
                if line.startswith('PRETTY_NAME='):
                    osname = line.split('=', 1)[1].strip('"')
        except OSError:
            pass
    return {'os': osname, 'kernel': '%s %s' % (platform.system(), platform.release()),
            'arch': platform.machine(), 'cpus': str(os.cpu_count() or '?'),
            'python': platform.python_version()}


def init(work, pairs):
    info = dict(p.split('=', 1) for p in pairs if '=' in p)
    info.update(system())
    with open(os.path.join(work, 'run.info'), 'w', encoding='utf-8') as f:
        for k in sorted(info):
            f.write('%s=%s\n' % (k, info[k].replace('\n', ' ')))
    return 0


def newest():
    base = os.environ.get('TMPDIR') or '/tmp'
    runs = [d for d in glob.glob(os.path.join(base, 'mutation.*')) if os.path.exists(os.path.join(d, 'list'))]
    return max(runs, key=os.path.getmtime) if runs else None


def alive(pid):
    try:
        os.kill(int(pid), 0)
        return True
    except (ValueError, OSError) as e:
        return isinstance(e, PermissionError)


def load(work):
    """The run as its files show it now."""
    r = {'work': work, 'info': kv(os.path.join(work, 'run.info')), 'now': time.time()}
    r['list'], r['expect'], r['file'] = [], {}, {}
    for line in rd(os.path.join(work, 'list')).splitlines():
        parts = line.split('\t')
        if len(parts) == 4:
            r['list'].append(parts[0]); r['file'][parts[0]] = parts[1]; r['expect'][parts[0]] = parts[3]
    r['res'], r['mtime'] = {}, {}
    rdir = os.path.join(work, 'res')
    for i in r['list']:
        p = os.path.join(rdir, i)
        if os.path.exists(p):
            f = (rd(p).rstrip('\n').split('\t') + ['', '', '', ''])[:4]
            r['res'][i] = f; r['mtime'][i] = os.path.getmtime(p)
    r['first'] = sorted(os.listdir(os.path.join(work, 'first'))) if os.path.isdir(os.path.join(work, 'first')) else []
    md = os.path.join(work, 'm')
    r['running'] = sorted(((d, os.path.getmtime(os.path.join(md, d))) for d in (os.listdir(md) if os.path.isdir(md) else [])
                          if d != 'base' and os.path.isdir(os.path.join(md, d))), key=lambda x: x[1])
    r['phases'] = []
    pp = os.path.join(work, 'phases')
    if os.path.exists(pp):
        for line in rd(pp).splitlines():
            f = line.split('\t')
            if len(f) >= 2 and f[1].isdigit():
                r['phases'].append((f[0], int(f[1]), f[2] if len(f) > 2 else ''))
    names = [p[0] for p in r['phases']]
    pid = r['info'].get('pid')
    if 'done' in names:
        r['state'] = 'finished, exit %s' % dict((p[0], p[2]) for p in r['phases'])['done']
    elif pid and alive(pid):
        r['state'] = 'running'
    elif pid:
        r['state'] = 'stopped: its process (%s) is gone and it wrote no summary' % pid
    else:
        r['state'] = 'unknown (no run.info: a run started before the progress report)'
    r['phase'] = r['phases'][-1] if r['phases'] else None
    return r


def under_load(f):
    """A kill run.sh re-runs alone, by its own rule (the summary's re-run block)."""
    v, by, why = f[1], f[2], f[3]
    return v in ('killed-abort', 'killed-timeout') or (v == 'killed' and by == 'merge-gate') \
        or (v == 'killed' and any(b in why for b in TIME_BOUND))


def counts(r):
    c = {'killed': 0, 'killed-abort': 0, 'killed-timeout': 0, 'survived': 0, 'failed': 0}
    unexpected, stale, by_suite = [], [], {}
    for i, f in r['res'].items():
        v = f[1]
        if v.startswith('killed'):
            c[v if v in c else 'killed'] += 1
            by_suite[f[2]] = by_suite.get(f[2], 0) + 1
            if r['expect'][i] != 'killed': stale.append(i)
        elif v == 'survived':
            c['survived'] += 1
            if r['expect'][i] == 'killed': unexpected.append(i)
        else:
            c['failed'] += 1
    return c, sorted(unexpected), sorted(stale), by_suite


def started(r, name):
    for p in r['phases']:
        if p[0] == name: return p[1]
    return None


def pace(r):
    """Done, total, per hour, seconds left and what is being counted, for the phase now."""
    n = len(r['list']); now = r['now']
    rerun = started(r, 'rerun')
    if rerun and 'summary' not in [p[0] for p in r['phases']]:
        ids = r['first']
        times = sorted(r['mtime'][i] for i in ids if r['mtime'].get(i, 0) >= rerun)
        done, total, t0, what = len(times), len(ids), rerun, 're-running alone'
    else:
        times = sorted(r['mtime'].values())
        done, total, t0, what = len(times), n, started(r, 'mutants') or (times[0] if times else now), 'mutants'
    recent = [t for t in times if t >= now - 1800]
    if len(recent) >= 5:
        rate = len(recent) / (max(now - max(now - 1800, t0), 60) / 3600)
    elif done and now > t0:
        rate = done / ((now - t0) / 3600)
    else:
        rate = 0
    left = (total - done) / rate * 3600 if rate else None
    return done, total, rate, left, what


def line(work):
    r = load(work)
    c, unexpected, _, _ = counts(r)
    done, total, rate, left, what = pace(r)
    pct = 100 * done // total if total else 0
    s = 'mutation: %s %d/%d (%d%%) · killed %d · survived %d (%d unexpected) · %d running' % (
        what, done, total, pct, c['killed'] + c['killed-abort'] + c['killed-timeout'], c['survived'], len(unexpected), len(r['running']))
    if rate: s += ' · %d/h' % rate
    if left is not None: s += ' · about %s left' % hm(left)
    print(s)
    return 0


def status(work):
    if not work:
        work = newest()
        if not work:
            print('no mutation run found: no mutation.* with a list under %s' % (os.environ.get('TMPDIR') or '/tmp'), file=sys.stderr)
            return 1
    if not os.path.exists(os.path.join(work, 'list')):
        print('%s is not a mutation run\'s work directory (it has no list)' % work, file=sys.stderr)
        return 1
    r = load(work); i = r['info']; now = r['now']
    c, unexpected, stale, by_suite = counts(r)
    done, total, rate, left, what = pace(r)
    n = len(r['list'])
    W = 11
    def row(k, v): print('  %-*s %s' % (W, k, v))
    print('mutation run  %s' % work)
    row('state', r['state'])
    if i:
        row('from', '%s · %s mutants (%s) · -j %s · %ss a suite before a timeout' % (
            i.get('from', '?'), i.get('n', n), 'the whole kit' if i.get('scope') == 'all' else 'a selection, ' + i.get('scope', '?'),
            i.get('j', '?'), i.get('timeout', '?')))
        st = int(i['started']) if i.get('started', '').isdigit() else None
        if st:
            end = started(r, 'done')
            row('started', '%s · %s %s' % (clock(st), 'ran' if end else 'running for', hm((end or now) - st)))
        row('system', '%s · %s %s · %s CPUs · bash %s · %s · Python %s' % (
            i.get('os', '?'), i.get('kernel', '?'), i.get('arch', ''), i.get('cpus', '?'), i.get('bash', '?'), i.get('git', '?'), i.get('python', '?')))
    try:
        row('load', 'now %.1f / %.1f / %.1f (1, 5, 15 min)' % os.getloadavg())
    except OSError:
        pass
    if r['phases']:
        parts = []
        for k, (name, t, d) in enumerate(r['phases']):
            t1 = r['phases'][k + 1][1] if k + 1 < len(r['phases']) else None
            if name == 'done':
                continue
            parts.append('%s %s%s%s' % (name, time.strftime('%H:%M', time.localtime(t)),
                                        ' (%s)' % hm(t1 - t) if t1 else ' (now, %s in)' % hm(now - t) if r['state'] == 'running' else '',
                                        ' — ' + d if d else ''))
        row('phases', parts[0])
        for p in parts[1:]: row('', p)
    bar = int(30 * done / total) if total else 0
    row('progress', '%s %d of %d %s (%d%%)' % ('█' * bar + '░' * (30 - bar), done, total, what, 100 * done // total if total else 0))
    if r['running']:
        row('running', ', '.join('%s (%s)' % (d, hm(now - t)) for d, t in r['running']))
    row('results', 'killed %d · killed by an abort %d · timed out %d · survived %d (%d expected, %d unexpected) · failed to apply %d · not yet run %d' % (
        c['killed'], c['killed-abort'], c['killed-timeout'], c['survived'], c['survived'] - len(unexpected), len(unexpected), c['failed'], n - len(r['res'])))
    queued = [m for m in r['res'] if under_load(r['res'][m])] if not started(r, 'rerun') else r['first']
    if queued and int(i.get('j', '1') or 1) > 1:
        row('re-runs', '%d kill(s) made under load %s alone (aborts, timeouts, merge-gate, time bounds); a re-run can turn one into a survivor' % (
            len(queued), 'will be run' if not started(r, 'rerun') else 'run'))
    if rate and r['state'] == 'running':
        row('rate', '%d an hour (the last 30 minutes, else the whole phase)' % rate)
    if left is not None and r['state'] == 'running':
        msg = 'about %s for the %s' % (hm(left), what)
        if what == 'mutants' and queued and done:
            per = (now - (started(r, 'mutants') or now)) * int(i.get('j', '1') or 1) / done
            msg += ', then about %s re-running %d alone (rough)' % (hm(len(queued) * per * 0.5), len(queued))
        row('left', msg)
    print()
    print('  by file (mutants done of total · killed · survived):')
    files = {}
    for m in r['list']:
        e = files.setdefault(r['file'][m], [0, 0, 0, 0])
        e[0] += 1
        if m in r['res']:
            e[1] += 1
            v = r['res'][m][1]
            if v.startswith('killed'): e[2] += 1
            elif v == 'survived': e[3] += 1
    for f, (tot, dn, k, s) in sorted(files.items(), key=lambda x: -x[1][0]):
        print('    %-44s %4d of %-4d · %4d · %3d' % (f, dn, tot, k, s))
    if by_suite:
        print()
        print('  killed, by the suite that killed it:')
        for s in sorted(by_suite, key=lambda x: -by_suite[x]):
            print('    %-44s %4d' % (s, by_suite[s]))
    print()
    if unexpected:
        for m in unexpected:
            print('  ❌ survived, expected killed: %s (%s) — logs in %s' % (m, r['file'][m], os.path.join(work, 'logs', m)))
    else:
        print('  unexpected survivors so far: none')
    for m in stale:
        print('  ⚠️  killed, expected to survive: %s — its expect needs updating' % m)
    return 0


def main(argv):
    cmd = argv[1] if len(argv) > 1 else ''
    if cmd == 'init' and len(argv) >= 3:
        return init(argv[2], argv[3:])
    if cmd == 'status':
        return status(argv[2] if len(argv) > 2 and argv[2] else None)
    if cmd == 'line' and len(argv) == 3:
        return line(argv[2])
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv))
