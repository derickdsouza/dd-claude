# Coordinator — Lane Allocation

Paste into one Claude session. The coordinator adds `drain:<name>` labels to beads to allocate `(wave, lane)` pairs to named worker agents. It does **not** work beads itself.

## State model

| Concept | How it's represented |
|---|---|
| Lane allocation | `drain:<name>` label on every bead in that lane |
| Un-allocated lane | no `drain:*` label on any bead in the lane |
| Bead claimed by worker | `status=in_progress` (set by `bd update --claim` inside the worker) |
| Bead done | `status=closed` |

## Commands

### 1 — Inspect lane × agent map

```bash
bd list --status=open --label-pattern 'drain:*' --json -n 0 \
  | python3 -c "
import json, sys
from collections import defaultdict
ds = json.load(sys.stdin)
rows = defaultdict(lambda: defaultdict(lambda: {'open':0,'ip':0}))
for d in ds:
    labels = d.get('labels') or []
    agent = next((l.split(':',1)[1] for l in labels if l.startswith('drain:')), None)
    wave  = next((l for l in labels if l.startswith('wave:')), '?')
    lane  = next((l for l in labels if l.startswith('lane:')), '?')
    if agent:
        rows[agent][(wave,lane)]['open'] += 1
        if d.get('status') == 'in_progress':
            rows[agent][(wave,lane)]['ip'] += 1
for agent, lanes in sorted(rows.items()):
    print(f'{agent}:')
    for (w,l), c in sorted(lanes.items()):
        print(f'  {w} {l}  open={c[\"open\"]}  in_progress={c[\"ip\"]}')
"
```

### 2 — Free lanes (no agent yet)

```bash
bd list --status=open --json -n 0 \
  | python3 -c "
import json, sys
from collections import defaultdict
ds = json.load(sys.stdin)
free = defaultdict(lambda: {'total':0, 'samples':[]})
for d in ds:
    labels = d.get('labels') or []
    if any(l.startswith('drain:') for l in labels): continue
    wave = next((l for l in labels if l.startswith('wave:')), None)
    lane = next((l for l in labels if l.startswith('lane:')), None)
    if wave and lane:
        key = (wave, lane)
        free[key]['total'] += 1
        if len(free[key]['samples']) < 2:
            free[key]['samples'].append(d['id'])
print(f'Free lanes: {len(free)}')
for (w,l), v in sorted(free.items(), key=lambda kv: -kv[1]['total']):
    print(f'  {w:<10} {l:<10}  {v[\"total\"]:>3} beads — e.g. {\",\".join(v[\"samples\"])}')
"
```

### 3 — Allocate: give `wave:N lane:X` to agent

```bash
WAVE=wave:1 LANE=lane:A AGENT=alpha

# Confirm free
bd list --status=open --label $WAVE --label $LANE --label-pattern 'drain:*' --json -n 0 \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print('already allocated' if d else 'free')"

# Allocate
bd list --status=open --label $WAVE --label $LANE --json -n 0 \
  | python3 -c "import json,sys; [print(i['id']) for i in json.load(sys.stdin)]" \
  | while read id; do bd update "$id" --add-label drain:$AGENT; done
```

### 4 — Release lane

```bash
AGENT=alpha
bd list --status=open --label drain:$AGENT --json -n 0 \
  | python3 -c "import json,sys; [print(i['id']) for i in json.load(sys.stdin)]" \
  | while read id; do bd update "$id" --remove-label drain:$AGENT; done
```

### 5 — Reassign lane

```bash
WAVE=wave:1 LANE=lane:A OLD=alpha NEW=beta
bd list --status=open --label $WAVE --label $LANE --label drain:$OLD --json -n 0 \
  | python3 -c "import json,sys; [print(i['id']) for i in json.load(sys.stdin)]" \
  | while read id; do
      bd update "$id" --remove-label drain:$OLD --add-label drain:$NEW
    done
```

### 6 — Progress report

```bash
bd list --status=open --label-pattern 'drain:*' --json -n 0 \
  | python3 -c "
import json, sys, subprocess, datetime
from collections import Counter, defaultdict
ds = json.load(sys.stdin)
per_agent = defaultdict(lambda: Counter())
for d in ds:
    labels = d.get('labels') or []
    agent = next((l.split(':',1)[1] for l in labels if l.startswith('drain:')), None)
    if not agent: continue
    per_agent[agent]['total'] += 1
    per_agent[agent][d.get('status','?')] += 1
today = datetime.date.today().isoformat()
closed_today = {}
for agent in per_agent:
    out = subprocess.check_output(['bd','list','--status=closed','--label',f'drain:{agent}',
                                   '--closed-after',today,'--json','-n','0'])
    closed_today[agent] = len(json.loads(out))
print(f'{\"AGENT\":<12} {\"OPEN\":>5} {\"IN_PROG\":>8} {\"CLOSED_TODAY\":>14}')
for agent in sorted(per_agent):
    c = per_agent[agent]
    print(f'{agent:<12} {c[\"open\"]:>5} {c[\"in_progress\"]:>8} {closed_today.get(agent,0):>14}')
"
```

### 7 — Bulk seed new agents

```bash
AGENTS=(alpha beta gamma delta)  # ← edit

bd list --status=open --json -n 0 \
  | python3 -c "
import json,sys
from collections import defaultdict
ds = json.load(sys.stdin)
free = defaultdict(list)
for d in ds:
    labels = d.get('labels') or []
    if any(l.startswith('drain:') for l in labels): continue
    wave = next((l for l in labels if l.startswith('wave:')), None)
    lane = next((l for l in labels if l.startswith('lane:')), None)
    if wave and lane: free[(wave, lane)].append(d['id'])
for (w,l), ids in sorted(free.items(), key=lambda kv: -len(kv[1])):
    print(f'{w}\t{l}\t{len(ids)}')" \
  | head -${#AGENTS[@]} > /tmp/allocation_plan.tsv

cat /tmp/allocation_plan.tsv  # review before applying

i=0
while IFS=$'\t' read -r wave lane count; do
  agent="${AGENTS[$i]}"
  echo "Allocating $wave $lane ($count beads) → drain:$agent"
  bd list --status=open --label "$wave" --label "$lane" --json -n 0 \
    | python3 -c "import json,sys; [print(i['id']) for i in json.load(sys.stdin)]" \
    | while read id; do bd update "$id" --add-label drain:$agent; done
  i=$((i+1))
done < /tmp/allocation_plan.tsv
```

## Operating rhythm

Every 15–30 min while workers are active:

1. **Inspect** (cmd 1) — where does each agent stand?
2. **Progress report** (cmd 6) — closed-today vs allocated-open
3. `in_progress=0 && open>0 for >1h` → likely stalled. Check `bd show <bead>` for blockers; spot-check the worker session.
4. `open=0 && in_progress=0` → agent is done. Allocate next free lane (cmd 3) or reassign a stalled one (cmd 5).
5. `free lanes = 0 && agents idle` → wave drained. Move to next wave.

## Rules

- **Wave ordering**: drain `wave:0` (foundations) before `wave:1`. Later waves depend on shared types/helpers.
- **One lane per agent at a time.** Don't give an agent both `wave:1 lane:A` and `wave:2 lane:B` — lanes are only conflict-free within the same wave.
- **Don't allocate across waves.** Release fully before reallocating.
- **`migration:NNNN` labels are sacred.** The classifier pre-allocates them to prevent parallel collisions on `_journal.json`.
- **Respect claims.** If a bead has `assignee != ""`, a worker has started it. Don't touch `drain:*` labels without coordinating with that worker.
