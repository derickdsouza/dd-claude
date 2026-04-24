"""
Beadswave wave/lane/shape/scope classifier — portable across repos.

Input:  /tmp/bd_open.json  (output of `bd list --status=open --json -n 0`)
Output: /tmp/apply_labels.sh  (shell script of `bd update ... --add-label ...`)

Labels emitted per bead:
  wave:N           — 0=foundation serial, 1=parallel single-file, 2=append-heavy,
                     4=big individuals, 9=triage (no file mentions)
  lane:A..Z        — file-disjoint bucket within (wave, scope, shape)
  shape:<tag>      — one of ~14 work-types (add/remove in SHAPE_ORDER below)
  scope:<pkg>      — package/layer (frontend, db-schema, backend-svc, py, ...)
  owns:<path>      — primary file path (shortened)
  foundation:true  — if >=FOUNDATION_REF_THRESHOLD beads reference it OR title matches
  touches-hotspot:<file> — bead touches a known contention file (may be repeated)
  migration:NNNN   — pre-allocated migration number for DB-schema beads

TO ADAPT FOR YOUR REPO: edit the "Tuning knobs" section below. The rest of the
script is mechanical and should not need changes.
"""
import json, os, re
from collections import defaultdict, Counter

# ═══════════════════════════════════════════════════════════════════════════
# ─── Tuning knobs ─ EDIT THESE FOR YOUR REPO ──────────────────────────────
# ═══════════════════════════════════════════════════════════════════════════

# Auto-detected from bead IDs. Finds the common prefix (everything before the
# last hyphen-separated segment) across all beads in the input.
# Override by setting BEADSWAVE_PROJECT_PREFIX in the environment.
PROJECT_PREFIX = None

# Files where two agents editing simultaneously would conflict. Common candidates:
#   - shared barrel/index files (src/index.ts)
#   - shared constants/config (endpoints, feature flags)
#   - DB schema registries (_journal.json)
#   - monitoring/alert rules (alerts.yml)
#   - protocol/parser files edited piecemeal
HOTSPOTS = set({
    # 'src/index.ts',
    # 'packages/shared/src/index.ts',
    # 'monitoring/prometheus/alerts.yml',
})

# A single specific file that, if touched, forces wave:4 regardless of file count
# (because it's so churn-prone that even a one-file bead deserves an isolated lane).
# Set to None if you don't have one.
BIG_FILE = None  # e.g. 'packages/backend/src/services/transaction-import-parsers.ts'

# First unused migration number in your repo. Find it with:
#   ls packages/backend/src/db/migrations/*.sql | tail -1
# Set to None if your repo has no SQL migrations.
MIGRATION_SEED = None  # e.g. 52

# Regex patterns for your repo's work-types. First match wins. Add/remove freely.
# Each entry is (tag, regex). The tag becomes `shape:<tag>` on matching beads.
SHAPE_ORDER = [
    ('withtz',            re.compile(r'withTimezone|timestamp\(.*\).*tz|timestamptz', re.I)),
    ('naive-dt-py',       re.compile(r'datetime\.now\(\)|datetime\.utcnow\(\)|naive datetime', re.I)),
    ('symbol-encode',     re.compile(r'encodeURIComponent|canonical.*symbol|Symbol.*encod', re.I)),
    ('metric-emit',       re.compile(r'counter|gauge|histogram|emit.*metric|Prometheus', re.I)),
    ('alert-rule',        re.compile(r'alerts?\.yml|alertmanager|runbook', re.I)),
    ('fk-ondelete',       re.compile(r'onDelete|foreign key.*cascade|FK.*onDelete', re.I)),
    ('retention-policy',  re.compile(r'retention (policy|days)|drop.*chunks', re.I)),
    ('zod-add',           re.compile(r'Zod|z\.object|schema.*validation', re.I)),
    ('idempotency',       re.compile(r'idempoten|unique constraint|dedup', re.I)),
    ('audit-ff',          re.compile(r'logUserAction|fire[- ]and[- ]forget', re.I)),
    ('error-shape',       re.compile(r'error (shape|response|contract)', re.I)),
    ('test-only',         re.compile(r'^Test gap|Boundary conformance test|Tests to write', re.I)),
    ('runbook',           re.compile(r'Runbook needed', re.I)),
]

# Titles that always mark a bead as foundation (wave:0), in addition to the
# automatic reference-count heuristic. Describe "shared infra" beads here.
FOUNDATION_TITLES = re.compile(
    r'canonical Symbol|branded type|shared (helper|constant|Zod)|'
    r'shared schema',
    re.I,
)

# A bead is also foundation if this many OTHER beads reference its 5-char ID suffix.
FOUNDATION_REF_THRESHOLD = 4

# Regex that matches a file path anywhere in your repo. Default covers most
# monorepo shapes. Extend the prefix group if you have additional top-level dirs.
PATH_RE = re.compile(
    r'(?:packages/[a-z_-]+/|src/|docs/|scripts/|spec/|monitoring/|\.beads/|apps/[a-z_-]+/|services/[a-z_-]+/)'
    r'[a-zA-Z0-9_./-]+?\.(?:ts|tsx|py|sql|yml|yaml|sh|md|json|css|rs|go|java|kt)'
)

# Directories whose paths are citations, not write targets — strip them from
# extracted file sets. Add your repo's equivalents.
CITATION_PREFIXES = (
    'docs/audits/',
    'docs/adr/',
    'docs/architecture/',
    'spec/',
    '.beads/',
)

# ═══════════════════════════════════════════════════════════════════════════
# ─── Below this line: mechanical classification. Should not need editing. ─
# ═══════════════════════════════════════════════════════════════════════════

# ─── Input ────────────────────────────────────────────────────────────
_snapshot_path = os.environ.get('BD_SNAPSHOT', '/tmp/bd_open.json')
with open(_snapshot_path) as f:
    issues = json.load(f)

# ─── Auto-detect project prefix ───────────────────────────────────────
if os.environ.get('BEADSWAVE_PROJECT_PREFIX'):
    PROJECT_PREFIX = os.environ['BEADSWAVE_PROJECT_PREFIX']
elif PROJECT_PREFIX is None and issues:
    _shorts = []
    for _i in issues:
        _parts = _i['id'].rsplit('-', 1)
        _shorts.append(_parts[0] + '-' if len(_parts) > 1 else '')
    PROJECT_PREFIX = _shorts[0] if len(set(_shorts)) == 1 else ''
elif PROJECT_PREFIX is None:
    PROJECT_PREFIX = ''

# ─── File extraction ──────────────────────────────────────────────────
def strip_citations(files):
    return {f for f in files if not any(f.startswith(p) for p in CITATION_PREFIXES)}

def extract_files(issue):
    text = (issue.get('title','') or '') + '\n' + (issue.get('description','') or '')
    return strip_citations({m.group(0) for m in PATH_RE.finditer(text)})

# ─── Shape classification ─────────────────────────────────────────────
def primary_shape(issue):
    text = (issue.get('title','') or '') + ' ' + (issue.get('description','') or '')
    for tag, pat in SHAPE_ORDER:
        if pat.search(text):
            return tag
    return 'adhoc'

# ─── Scope (derive from file paths) ───────────────────────────────────
def scope_of(files):
    pkgs = set()
    for f in files:
        m = re.match(r'(?:packages|apps|services)/([a-z_-]+)/', f)
        if m:
            pkgs.add(m.group(1))
    if not pkgs:
        if any(f.startswith('scripts/') for f in files):    return 'scripts'
        if any(f.startswith('monitoring/') for f in files): return 'infra'
        if any(f.startswith('src/') for f in files):        return 'root'
        return 'unknown'
    if len(pkgs) == 1:
        pkg = next(iter(pkgs))
        if any(f'/{pkg}/' in f and '/db/schema/' in f for f in files):     return 'db-schema'
        if any(f'/{pkg}/' in f and '/db/migrations/' in f for f in files): return 'db-migration'
        if any(f'/{pkg}/' in f and '/routes/' in f for f in files):        return f'{pkg}-routes'
        if any(f'/{pkg}/' in f and '/services/' in f for f in files):      return f'{pkg}-svc'
        if any(f'/{pkg}/' in f and '/__tests__/' in f for f in files):     return f'{pkg}-tests'
        if any(f'/{pkg}/' in f and '/lib/' in f for f in files):           return f'{pkg}-lib'
        return pkg
    return 'cross-pkg'

# ─── Foundation detection ─────────────────────────────────────────────
ALL_IDS = {i['id'].replace(PROJECT_PREFIX, '') for i in issues}
refs = defaultdict(set)
for i in issues:
    src = i['id'].replace(PROJECT_PREFIX, '')
    text = (i.get('description','') or '') + ' ' + (i.get('title','') or '')
    for ref in re.findall(r'\b([0-9a-z]{5})\b', text):
        if ref != src and ref in ALL_IDS:
            refs[ref].add(src)

def is_foundation(issue):
    src = issue['id'].replace(PROJECT_PREFIX, '')
    if len(refs[src]) >= FOUNDATION_REF_THRESHOLD:
        return True
    if FOUNDATION_TITLES.search((issue.get('title','') or '')):
        return True
    return False

# ─── Primary file (owns) ──────────────────────────────────────────────
def owns_file(files):
    if not files: return None
    non_test = [f for f in files if '/__tests__/' not in f and not f.endswith('.md')]
    pool = non_test or list(files)
    return sorted(pool, key=lambda f: (len(f), f))[0]

# ─── Migration-producing ──────────────────────────────────────────────
def needs_migration(issue, files):
    if MIGRATION_SEED is None:
        return False
    text = (issue.get('title','') or '') + ' ' + (issue.get('description','') or '')
    touches_schema = any('/db/schema/' in f for f in files)
    touches_migration = any('/db/migrations/' in f for f in files)
    kw = (any(k in text for k in ['withTimezone', 'timestamptz', 'TIMESTAMP WITH TIME ZONE'])
          or re.search(r'onDelete\s*[:=]|FK.*onDelete', text))
    retention = re.search(r'add_retention_policy|retention.*hypertable', text)
    uniq = re.search(r'add (unique|UNIQUE) (constraint|index)|ALTER TABLE.*ADD CONSTRAINT', text)
    if touches_migration: return True
    if touches_schema and (kw or uniq): return True
    if retention: return True
    return False

# ─── Build per-bead analysis ──────────────────────────────────────────
rows = []
for i in issues:
    files = extract_files(i)
    rows.append({
        'id': i['id'].replace(PROJECT_PREFIX, ''),
        'pri': i.get('priority', 9),
        'title': (i.get('title','') or '')[:100],
        'files': files,
        'file_count': len(files),
        'scope': scope_of(files),
        'shape': primary_shape(i),
        'hotspot': bool(files & HOTSPOTS),
        'hotspot_files': sorted(files & HOTSPOTS),
        'owns': owns_file(files),
        'foundation': is_foundation(i),
        'refcount': len(refs[i['id'].replace(PROJECT_PREFIX, '')]),
        'needs_migration': needs_migration(i, files),
    })

# ─── Wave assignment ──────────────────────────────────────────────────
def wave_of(r):
    if r['foundation']: return 0
    if r['file_count'] >= 4: return 4
    if BIG_FILE and BIG_FILE in r['files']: return 4
    if r['hotspot']: return 2
    if r['needs_migration']: return 2
    if r['shape'] in ('metric-emit', 'alert-rule', 'runbook'): return 2
    if r['file_count'] == 0: return 9
    return 1

for r in rows:
    r['wave'] = wave_of(r)

# ─── Lane assignment via greedy graph coloring ────────────────────────
def assign_lanes():
    by_wave = defaultdict(list)
    for r in rows:
        by_wave[r['wave']].append(r)
    for wave, rs in by_wave.items():
        grouped = defaultdict(list)
        for r in rs:
            grouped[(r['scope'], r['shape'])].append(r)
        lane_counter = 0
        letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
        for (scope, shape), items in sorted(grouped.items(), key=lambda kv: -len(kv[1])):
            items.sort(key=lambda x: (x['pri'], x['file_count']))
            lanes = []
            for it in items:
                placed = False
                for ln in lanes:
                    if not (it['files'] & ln['files']):
                        ln['items'].append(it)
                        ln['files'] |= it['files']
                        placed = True
                        break
                if not placed:
                    lanes.append({'files': set(it['files']), 'items': [it]})
            for ln in lanes:
                letter = letters[lane_counter % 26]
                lane_counter += 1
                for it in ln['items']:
                    it['lane'] = letter
                    it['lane_group'] = f"{scope}/{shape}"

assign_lanes()

# ─── Migration number allocator ───────────────────────────────────────
if MIGRATION_SEED is not None:
    mig_items = sorted([r for r in rows if r['needs_migration']],
                       key=lambda x: (x['pri'], x['id']))
    next_mig = MIGRATION_SEED
    for r in rows:
        r['migration_num'] = None
    for m in mig_items:
        m['migration_num'] = f"{next_mig:04d}"
        next_mig += 1
else:
    mig_items = []
    for r in rows:
        r['migration_num'] = None

# ─── Emit bd update commands ──────────────────────────────────────────
out_lines = []
for r in rows:
    labels = [
        f"wave:{r['wave']}",
        f"lane:{r.get('lane','_')}",
        f"shape:{r['shape']}",
        f"scope:{r['scope']}",
    ]
    if r['foundation']:
        labels.append("foundation:true")
    if r['hotspot']:
        for hf in r['hotspot_files']:
            short = hf.split('/')[-1].replace('.yml', '').replace('.ts', '').replace('.json', '')
            labels.append(f"touches-hotspot:{short}")
    if r['owns']:
        owns_short = (r['owns'].replace('packages/', '').replace('src/', '')
                      .replace('.ts', '').replace('.py', '').replace('.tsx', ''))
        labels.append(f"owns:{owns_short}")
    if r['migration_num']:
        labels.append(f"migration:{r['migration_num']}")
    label_args = ' '.join(f'--add-label {l}' for l in labels)
    out_lines.append(f"bd update {PROJECT_PREFIX}{r['id']} {label_args}")

with open('/tmp/apply_labels.sh', 'w') as f:
    f.write('#!/usr/bin/env bash\nset -e\n')
    f.write('# Auto-generated: apply wave/lane/shape/scope labels to all open beads.\n')
    f.write(f'# Total: {len(out_lines)} bead updates\n\n')
    for ln in out_lines:
        f.write(ln + '\n')

# ─── Summary ──────────────────────────────────────────────────────────
print(f"Generated {len(out_lines)} bd update commands → /tmp/apply_labels.sh\n")
wave_counts = Counter(r['wave'] for r in rows)
wave_names = {0: 'foundations (serial)', 1: 'parallel single-file', 2: 'append-heavy',
              4: 'big individuals',      9: 'triage (no files)'}
print("WAVE DISTRIBUTION:")
for w in sorted(wave_counts):
    print(f"  Wave {w} [{wave_names.get(w, '?')}]: {wave_counts[w]} beads")

print("\nLANES PER WAVE:")
for w in sorted(wave_counts):
    lanes = defaultdict(list)
    for r in rows:
        if r['wave'] == w:
            lanes[(r.get('lane', '_'), r.get('lane_group', '?'))].append(r)
    if lanes:
        print(f"\n  Wave {w}: {len(lanes)} lanes")
        for (lane, group), rs in sorted(lanes.items(), key=lambda kv: -len(kv[1]))[:12]:
            print(f"    lane:{lane} [{group}] — {len(rs)} beads — e.g. {rs[0]['id']} ({rs[0]['title'][:50]})")

if MIGRATION_SEED is not None:
    print(f"\nMIGRATION NUMBERS ALLOCATED: {len(mig_items)} beads, "
          f"range {MIGRATION_SEED:04d}–{(MIGRATION_SEED + len(mig_items) - 1):04d}")
    for m in mig_items[:10]:
        print(f"  migration:{m['migration_num']} → {m['id']} ({m['title'][:60]})")
    if len(mig_items) > 10:
        print(f"  ... +{len(mig_items)-10} more")
