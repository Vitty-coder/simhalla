#!/usr/bin/env bash
# Regenera tests/golden/duel_a_vs_b_seed42.json. Usar SOLO tras un cambio intencionado de reglas/motor.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$(command -v godot || echo "$HOME/tools/godot/godot")}"
"$GODOT" --headless --path . --script res://tools/run_duel.gd -- attacker_a.json attacker_b.json 42 --json 2>/dev/null \
  | sed -n '/^{/,$p' | python3 -c '
import json,sys
r=json.load(sys.stdin)
g={k:r[k] for k in ("log_hash","winner_team","turns","events","outcome","reason","engine_version")}
g["ruleset"]=r["ruleset"]
json.dump(g,open("tests/golden/duel_a_vs_b_seed42.json","w"),indent=2); print(json.dumps(g,indent=2))'
