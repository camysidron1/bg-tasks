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
BG_OUT=$(bg --setup)
[[ -d "$PROJ/To-Dos" ]] || fail "To-Dos not created"
grep -q "To-Dos/" "$PROJ/.gitignore" || fail ".gitignore not updated"
pass "setup ok"

step "bg (no args) creates default task and sets active"
bg || true
DEF_FILE=$(ls -1t "$PROJ/To-Dos"/*.md | head -1)
[[ -f "$DEF_FILE" ]] || fail "default task missing"
grep -q '^Status: active' "$DEF_FILE" || fail "default task not active"
pass "default task created and active"

step "bg alpha creates new task and marks previous pending"
sleep 1
bg alpha || true
ALPHA_FILE=$(ls -1t "$PROJ/To-Dos"/*_alpha.md | head -1)
[[ -f "$ALPHA_FILE" ]] || fail "alpha task missing"
[[ "$(cat "$PROJ/To-Dos/.active")" == "$ALPHA_FILE" ]] || fail "alpha not active"
! grep -q '^Status: active' "$DEF_FILE" || fail "previous still active"
grep -q '^Status: pending' "$DEF_FILE" || fail "previous not pending"
pass "alpha active, previous pending"

step "bg --status shows active and latest"
STATUS=$(bg --status)
print -r -- "$STATUS" | grep -q "Active: *$(basename "$ALPHA_FILE")" || fail "status missing active"
pass "status ok"

step "bg task show alpha prints contents"
SHOW=$(bg task show alpha)
print -r -- "$SHOW" | grep -q "# Task: alpha" || fail "show did not print alpha"
pass "show ok"

step "bg task pending marks active pending"
bg task pending
grep -q '^Status: pending' "$ALPHA_FILE" || fail "alpha not pending"
pass "pending ok"

step "bg task complete marks active complete and adds Completed timestamp"
bg task complete
grep -q '^Status: complete' "$ALPHA_FILE" || fail "alpha not complete"
grep -q '^Completed:' "$ALPHA_FILE" || fail "Completed timestamp missing"
pass "complete ok"

step "bg task clear deletes latest with confirmation and updates active"
# Create another task to be latest
sleep 1; bg beta || true
BETA_FILE=$(ls -1t "$PROJ/To-Dos"/*_beta.md | head -1)
[[ -f "$BETA_FILE" ]] || fail "beta task missing"
echo y | bg task clear
[[ ! -f "$BETA_FILE" ]] || fail "beta file not deleted"
pass "task clear ok"

step "bg -ai gamma creates AI-prefilled task (stubbed)"
function curl() {
  printf '%s' '{"content":[{"text":"# Task: gamma\nCreated: TEST\n## Description\nAI body\n## Progress\n- [ ] step\n## Notes\n"}]}'
}
export ANTHROPIC_API_KEY=dummy
sleep 1; bg -ai gamma || true
GAMMA_FILE=$(ls -1t "$PROJ/To-Dos"/*_gamma.md | head -1)
[[ -f "$GAMMA_FILE" ]] || fail "gamma task missing"
grep -q '^Status: active' "$GAMMA_FILE" || fail "gamma not active"
pass "ai create ok"

step "bg clear deletes all with confirmation"
echo y | bg clear
[[ -z "$(ls -1 "$PROJ/To-Dos"/*.md 2>/dev/null || true)" ]] || fail "tasks not cleared"
pass "clear all ok"

print -r -- "${GREEN}All tests passed${RESET}"
