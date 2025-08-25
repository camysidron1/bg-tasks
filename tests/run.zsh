#!/usr/bin/env zsh
set -euo pipefail

# Colors
RED=$'%{[31m%}'; GREEN=$'%{[32m%}'; YELLOW=$'%{[33m%}'; RESET=$'%{[0m%}'
pass() { print -r -- "${GREEN}PASS${RESET} $1"; }
fail() { print -r -- "${RED}FAIL${RESET} $1"; exit 1; }

# Setup temp HOME and project
TMPROOT=$(mktemp -d 2>/dev/null || mktemp -d -t bgtest)
export HOME="$TMPROOT/home"; mkdir -p "$HOME"
export HISTFILE="$HOME/.zsh_history"; : > "$HISTFILE"
PROJ="$TMPROOT/proj"; mkdir -p "$PROJ/.git"
: > "$PROJ/.gitignore"

# Load function and stub editor and AI network
alias vim=:
source "$(pwd)/templates/bg-function.sh"

step() { print -r -- "${YELLOW}-- $1 --${RESET}"; }

cd "$PROJ"

step "bg --setup creates To-Dos and updates .gitignore"
BG_OUT=$(bgt --setup)
[[ -d "$PROJ/To-Dos" ]] || fail "To-Dos not created"
grep -q "To-Dos/" "$PROJ/.gitignore" || fail ".gitignore not updated"
pass "setup ok"

step "bg (no args) creates default task and sets active"
bgt || true
DEF_FILE=$(ls -1t "$PROJ/To-Dos"/*.md | head -1)
[[ -f "$DEF_FILE" ]] || fail "default task missing"
grep -q '^Status: active' "$DEF_FILE" || fail "default task not active"
pass "default task created and active"

step "bgt task new alpha creates new task and marks previous pending"
sleep 1
bgt task new alpha || true
ALPHA_FILE=$(ls -1t "$PROJ/To-Dos"/*_alpha.md | head -1)
[[ -f "$ALPHA_FILE" ]] || fail "alpha task missing"
[[ "$(cat "$PROJ/To-Dos/.active")" == "$ALPHA_FILE" ]] || fail "alpha not active"
! grep -q '^Status: active' "$DEF_FILE" || fail "previous still active"
grep -q '^Status: pending' "$DEF_FILE" || fail "previous not pending"
pass "alpha active, previous pending"

step "bg --status shows active and latest"
STATUS=$(bgt --status)
print -r -- "$STATUS" | grep -q "Active: *$(basename "$ALPHA_FILE")" || fail "status missing active"
pass "status ok"

step "bg task show alpha prints contents"
SHOW=$(bgt task show alpha)
print -r -- "$SHOW" | grep -q "# Task: alpha" || fail "show did not print alpha"
pass "show ok"

step "bg task select up moves to older (previous) task"
bgt task select up || true
[[ "$(basename "$(cat "$PROJ/To-Dos/.active")")" == "$(basename "$DEF_FILE")" ]] || fail "select up did not activate older task"
pass "select up ok"

step "bg task select down returns to newer task"
bgt task select down || true
[[ "$(basename "$(cat "$PROJ/To-Dos/.active")")" == "$(basename "$ALPHA_FILE")" ]] || fail "select down did not activate newer task"
pass "select down ok"

step "bg task select 1 selects top (newest)"
bgt task select 1 || true
[[ "$(basename "$(cat "$PROJ/To-Dos/.active")")" == "$(basename "$ALPHA_FILE")" ]] || fail "select 1 not top"
pass "select 1 ok"

step "bg task select bottom selects oldest"
bgt task select bottom || true
[[ "$(basename "$(cat "$PROJ/To-Dos/.active")")" == "$(basename "$DEF_FILE")" ]] || fail "select bottom not oldest"
pass "select bottom ok"

# Restore active to newest (alpha) before status tests
step "bg task select top selects newest (alpha) before status tests"
bgt task select top || true
[[ "$(cat "$PROJ/To-Dos/.active")" == "$ALPHA_FILE" ]] || fail "select top did not activate alpha"
pass "select top ok"

step "bg task pending marks active pending"
bgt task pending
grep -q '^Status: pending' "$ALPHA_FILE" || fail "alpha not pending"
pass "pending ok"

step "bg task complete marks active complete and adds Completed timestamp"
bgt task complete
grep -q '^Status: complete' "$ALPHA_FILE" || fail "alpha not complete"
grep -q '^Completed:' "$ALPHA_FILE" || fail "Completed timestamp missing"
pass "complete ok"

step "bg task clear deletes latest with confirmation and updates active"
# Create another task to be latest
sleep 1; bgt task new beta || true
BETA_FILE=$(ls -1t "$PROJ/To-Dos"/*_beta.md | head -1)
[[ -f "$BETA_FILE" ]] || fail "beta task missing"

step "bg continue sets latest active and previous pending"
# Switch active back to alpha to simulate working on older task
bgt task open alpha || true
bgt continue || true
[[ "$(cat "$PROJ/To-Dos/.active")" == "$BETA_FILE" ]] || fail "continue didn't activate latest"
# Verify statuses immediately after continue
grep -q '^Status: pending' "$ALPHA_FILE" || fail "previous not pending after continue"
grep -q '^Status: active' "$BETA_FILE" || fail "latest not active after continue"
pass "continue ok"

step "bg task select $(basename $ALPHA_FILE) selects by filename"
bgt task select "$(basename "$ALPHA_FILE")" || true
[[ "$(cat "$PROJ/To-Dos/.active")" == "$ALPHA_FILE" ]] || fail "select by filename failed"
pass "select by filename ok"

echo y | bgt task clear
[[ ! -f "$BETA_FILE" ]] || fail "beta file not deleted"
pass "task clear ok"

step "bg -ai gamma creates AI-prefilled task (stubbed)"
function curl() {
  printf '%s' '{"content":[{"text":"# Task: gamma\nCreated: TEST\n## Description\nAI body\n## Progress\n- [ ] step\n## Notes\n"}]}'
}
export ANTHROPIC_API_KEY=dummy
sleep 1; bgt -ai task new gamma || true
GAMMA_FILE=$(ls -1t "$PROJ/To-Dos"/*_gamma.md | head -1)
[[ -f "$GAMMA_FILE" ]] || fail "gamma task missing"
grep -q '^Status: active' "$GAMMA_FILE" || fail "gamma not active"
pass "ai create ok"

step "bg clear deletes all with confirmation"
echo y | bgt clear
[[ -z "$(ls -1 "$PROJ/To-Dos"/*.md 2>/dev/null || true)" ]] || fail "tasks not cleared"
pass "clear all ok"

print -r -- "${GREEN}All tests passed${RESET}"
