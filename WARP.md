# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

Repository: bgt-task — a small npm package whose core functionality is a Zsh function (bgt) for lightweight task management stored under To-Dos/ in a project. The Node scripts only handle install/uninstall of the shell integration.

1) Common commands

- Install deps (local development)
  - npm install
- Run tests (safe: tests sandbox HOME; does not touch your real shell config)
  - npm test
  - Or: zsh tests/run.zsh
- Run a focused/manual check (no dedicated single-test runner)
  - In a temporary shell, source the function and run a specific flow without opening an editor:
    - zsh -lc 'alias vim=:
      export TMPROOT=$(mktemp -d 2>/dev/null || mktemp -d -t bgt); export HOME="$TMPROOT/home"; mkdir -p "$HOME"; export HISTFILE="$HOME/.zsh_history";
      mkdir -p "$TMPROOT/proj/.git"; : > "$TMPROOT/proj/.gitignore"; cd "$TMPROOT/proj";
      source ./templates/bg-function.sh; bgt --setup; bgt --no-open task new demo-task; bgt --status'
- Lint/format
  - None configured.
- Build/package
  - None required to run tests. To test global install behavior locally, prefer npm link (note: running installer alters shell config):
    - npm link        # Will execute postinstall and update your shell config; only do this intentionally
    - npm unlink -g bgt-task && node ./bin/uninstall.js  # Removes shell snippet written by the installer

2) High-level architecture

- CLI entrypoint is a Zsh function, not Node.
  - Source: templates/bg-function.sh defines bgt() with subcommands and helpers.
  - Persisted into user's config by installer as ~/.config/bgt-task/bgt.zsh and sourced from the user’s shell rc.
- Install/uninstall (Node):
  - bin/install.js
    - Detects shell rc (~/.zshrc, ~/.bashrc, or fish) and inserts a bounded snippet between markers:
      - # >>> bgt-task start >>>
      - # <<< bgt-task end <<<
    - Writes the function file to ~/.config/bgt-task/bgt.zsh.
    - Validates Zsh config (zsh -n) and rolls back on failure; backs up rc with timestamped .bg-task.bak.
    - Removes legacy embedded function and old markers if present before adding the new snippet.
  - bin/uninstall.js
    - Removes the bounded snippet from known shell configs and deletes ~/.config/bgt-task/bgt.zsh.
- Core behavior (Zsh function):
  - Project root detection: walks up to find a .git directory; falls back to $PWD.
  - Task storage: To-Dos/ directory at project root; active pointer file: To-Dos/.active.
  - Task files: timestamped Markdown: YYYY-MM-DD_HH-MM-SS_<name>.md with Status: lines updated via sed/awk.
- Commands (non-exhaustive, essentials):
    - bgt --setup: create To-Dos/, update .gitignore, attempt to load .env files, report AI availability.
    - bgt: open latest and set active (does not create by name anymore).
    - bgt task new <name>: create a task; combine with -ai or --sections-*.
    - bgt --status: show project root, To-Dos path, active/latest, and recent tasks.
    - bgt continue or bgt task continue: set latest active; optional agent hook.
    - bgt task show|open [fragment]: print/open a matching or active/latest task; open sets active.
    - bgt task select <up|down|top|bottom|index|fragment|filepath>: select a different task as active using stack traversal.
    - bgt task pending|complete: update Status (complete also appends Completed: timestamp).
    - bgt task clear: delete latest (interactive confirm; updates active pointer appropriately).
    - bgt clear: delete all task files in To-Dos/ (interactive confirm).
  - Editor: the function invokes vim by name; use --no-open for non-interactive runs or alias vim to your editor.
  - AI path: optional Anthropic call via curl (model: claude-3-5-sonnet-20241022); requires ANTHROPIC_API_KEY in env; jq used to encode request. If missing or API fails, falls back to default template.
  - Sections-driven creation: --sections-json <file> or --sections-stdin expects JSON; renders arrays as checklists (requires jq).
  - Agent hook: if BGT_AGENT_CMD is set, it is eval'd; otherwise ~/.config/bgt-task/agent.zsh is sourced and bgt_agent_continue is invoked if defined.
- Tests: tests/run.zsh
  - Creates an isolated $HOME and project, aliases vim to a no-op, stubs curl for AI, and exercises the function end-to-end. This is the recommended way to validate changes safely.

3) Important notes distilled from README.md

- Installation for end users: npm install -g bgt-task (runs installer which modifies shell config and writes ~/.config/bgt-task/bgt.zsh).
- AI setup: export or put in .env at project root: ANTHROPIC_API_KEY=<key>.
- Directory usage: To-Dos/ is created at project root and added to .gitignore; active pointer lives at To-Dos/.active.

4) Developing safely in this repo (Warp-specific hints)

- Prefer running npm test (or zsh tests/run.zsh) during development; it runs in a sandboxed HOME and won’t alter your real shell config.
- Avoid invoking bin/install.js directly in your normal environment unless you intend to modify your shell rc; use a temp HOME if you must experiment:
  - HOME=$(mktemp -d)/home SHELL=/bin/zsh node bin/install.js
- When manually exercising bgt, alias vim to your preferred editor or use --no-open.

5) Workflow: adding new functionality and releasing

Follow the CLI shape: bgt <object> <command> [--flags]
- Examples: bgt task new <name>, bgt task clear, bgt task show, bgt task select
  - task select supports: up/down/top/bottom, 1-based index, name fragment, or filepath.

Step-by-step

1. Add the new functionality
- Edit templates/bg-function.sh
  - Add or extend a case branch under the appropriate object (e.g., the task) within the main argument parser.
  - Keep the interface consistent with bgt <object> <command> [--flags].
  - Update helpers as needed; maintain non-interactive paths via --no-open.

2. Update tests to cover the new functionality
- Modify tests/run.zsh to add an explicit step that exercises and verifies the new command.
  - Tests already sandbox HOME, alias vim=:, and create a temp git repo; mimic existing steps for structure and assertions.
- Run focused/manual checks if helpful (see Common commands for a temp-shell example).

3. Ensure tests pass
- npm test
- Or: zsh tests/run.zsh

4. Update --help to document the new functionality
- In templates/bg-function.sh, update _print_help to list the new command under the correct section.
- If you surface a brief command list during setup (_setup_bg_environment), update that summary as well.

5. Push changes to remote
- git checkout -b feat/<slug>
- git add -A && git commit -m "feat: <short description>"
- git push --set-upstream origin feat/<slug>

6. Publish a new npm version
- Bump version (creates a tag):
  - npm version patch   # or minor | major
- Push commit and tags:
  - git push --follow-tags
- Publish:
  - npm publish --access public
- Optional (safe install test in a temp HOME, since postinstall edits shell rc):
  - HOME=$(mktemp -d)/home SHELL=/bin/zsh npm i -g bgt-task@<new-version>

