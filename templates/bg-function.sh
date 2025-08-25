# Enhanced bg function with AI support and smart setup
bgt() {
    # Function to find project root (looks for .git directory)
    _find_project_root() {
        local current_dir="$(pwd)"
        while [[ "$current_dir" != "/" ]]; do
            if [[ -d "$current_dir/.git" ]]; then
                echo "$current_dir"
                return 0
            fi
            current_dir="$(dirname "$current_dir")"
        done
        # If no .git found, use current directory
        echo "$(pwd)"
    }
    
    local project_root="$(_find_project_root)"
    local todos_dir="$project_root/To-Dos"
    local use_ai=false
    local setup_mode=false
    local sections_mode=false
    local sections_json=""
    local no_open=false
    
    # Function to load environment variables from .env files
    _load_env_file() {
        local env_file="$1"
        if [[ -f "$env_file" ]]; then
            echo "🔧 Loading environment from: $(basename "$env_file")"
            # Export variables from .env file, ignoring comments and empty lines
            while IFS= read -r line || [[ -n "$line" ]]; do
                # Skip empty lines and comments
                [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
                # Export the variable if it contains =
                if [[ "$line" =~ ^[^=]+= ]]; then
                    export "$line"
                fi
            done < "$env_file"
            return 0
        fi
        return 1
    }

    # Find latest task file (by timestamped filename)
    _find_latest_task() {
        print -rl -- "$todos_dir"/*.md(N) | sort -r | head -1
    }

    # List tasks newest-first by filename timestamp (stable across edits)
    _list_tasks_desc() {
        print -rl -- "$todos_dir"/*.md(N) | sort -r
    }

    # Active task pointer helpers
    _active_pointer_file() {
        echo "$todos_dir/.active"
    }

    _set_active() {
        local file="$1"
        echo "$file" > "$(_active_pointer_file)"
    }

    _get_active() {
        local p="$(_active_pointer_file)"
        if [[ -f "$p" ]]; then
            cat "$p"
        else
            _find_latest_task
        fi
    }

    # Update Status: line in a task file
    _update_status() {
        local file="$1"
        local new_status="$2"
        if [[ -f "$file" ]]; then
            if grep -q '^Status:' "$file"; then
                sed -i '' -e "s/^Status:.*/Status: ${new_status}/" "$file"
            else
                # Insert after Created line
                awk -v s="Status: ${new_status}" 'NR==1{print;next} NR==2{print; print s; next} {print}' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
            fi
            if [[ "$new_status" == "complete" ]] && ! grep -q '^Completed:' "$file"; then
                echo "Completed: $(date)" >> "$file"
            fi
        fi
    }

    _print_status() {
        local latest="$(_find_latest_task)"
        local active="$(_get_active)"
        echo "Project root: $project_root"
        echo "To-Dos dir:   $todos_dir"
        if [[ -n "$active" ]]; then
            local status_line=$(grep -m1 '^Status:' "$active" 2>/dev/null | awk -F': ' '{print $2}')
            [[ -z "$status_line" ]] && status_line="unknown"
            echo "Active:       $(basename "$active") [${status_line}]"
        else
            echo "Active:       none"
        fi
        if [[ -n "$latest" ]]; then
            echo "Latest:       $(basename "$latest")"
        fi
        echo "Recent tasks:"
        _list_tasks_desc | head -5 | while read -r f; do
            local st=$(grep -m1 '^Status:' "$f" 2>/dev/null | awk -F': ' '{print $2}')
            [[ -z "$st" ]] && st="unknown"
            echo "  - $(basename "$f") [${st}]"
        done
    }

    # Create a task (optionally AI/sections). Usage: _create_task <name>
    _create_task() {
        local task_name="$1"
        # If latest already matches name, just open and set active
        local latest_file="$(_find_latest_task)"
        if [[ -n "$latest_file" ]] && echo "$latest_file" | grep -q "_${task_name}\.md$"; then
            _set_active "$latest_file"
            if [[ "$no_open" == false ]]; then
                vim "$latest_file"
            fi
            return 0
        fi

        local filename="$todos_dir/$(date +"%Y-%m-%d_%H-%M-%S")_${task_name}.md"

        # If sections were provided, disable AI path
        if [[ "$sections_mode" == true ]]; then
            use_ai=false
        fi

        # Auto-load .env files if available and not already loaded (safe under set -u)
        if [[ -z "${ANTHROPIC_API_KEY-}" && "$use_ai" == true ]]; then
            local env_files=("$project_root/.env" "$project_root/local.env" "$project_root/.env.local")
            for env_file in "${env_files[@]}"; do
                _load_env_file "$env_file" >/dev/null
            done
        fi

        if [[ "$use_ai" == true ]]; then
            echo "🤖 Generating AI-powered task template..."
            local prev_active="$(_get_active)"
            if [[ -z "${ANTHROPIC_API_KEY-}" ]]; then
                echo "⚠️  ANTHROPIC_API_KEY not found. Using default template."
                echo "   Run 'bgt --setup' for setup instructions."
                use_ai=false
            else
                local history_context=""
                history_context=$(fc -ln -50 2>/dev/null | grep -v ' bgt ' | tail -20)
                if [[ -z "$history_context" && -r ${HISTFILE:-$HOME/.zsh_history} ]]; then
                    history_context=$(tail -n 50 "${HISTFILE:-$HOME/.zsh_history}" 2>/dev/null | sed 's/^: [0-9]*:[0-9]*;//' | grep -v ' bgt ' | tail -20)
                fi
                local current_dir=$(pwd)
                local git_status=""
                if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
                    git_status=$(git status --porcelain 2>/dev/null | head -10)
                fi
                local ai_prompt="You are helping create a development task based on recent terminal activity.

Context:
- Current directory: $current_dir
- Task name: $task_name
- Recent terminal commands:
$history_context

Git status (if available):
$git_status

Please create a concise but thorough task description in markdown format with the following structure:

# Task: $task_name
Created: $(date)

## Description
[2-3 sentences describing what this task involves based on the terminal context]

## Progress
- [ ] [First actionable step based on context]
- [ ] [Second actionable step]
- [ ] [Third actionable step if relevant]

## Notes
[Any relevant technical notes, file paths, or context from the terminal history]

Be specific and actionable. If the terminal history shows specific files, commands, or errors, reference them."
                local ai_response=$(curl -s -X POST https://api.anthropic.com/v1/messages \
                    -H "Content-Type: application/json" \
                    -H "x-api-key: $ANTHROPIC_API_KEY" \
                    -H "anthropic-version: 2023-06-01" \
                    -d "{\"model\": \"claude-3-5-sonnet-20241022\", \"max_tokens\": 1000, \"messages\": [{ \"role\": \"user\", \"content\": $(echo "$ai_prompt" | jq -Rs .)}]}" 2>/dev/null | jq -r '.content[0].text' 2>/dev/null)
                if [[ -n "$ai_response" && "$ai_response" != "null" && "$ai_response" != "" ]]; then
                    echo "$ai_response" > "$filename"
                    if ! grep -q '^Status:' "$filename" 2>/dev/null; then
                        awk 'NR==1{print;next} NR==2{print; print "Status: active"; next} {print}' "$filename" > "$filename.tmp" && mv "$filename.tmp" "$filename"
                    else
                        _update_status "$filename" "active"
                    fi
                    if [[ -n "$prev_active" ]]; then
                        _update_status "$prev_active" "pending"
                    fi
                    _set_active "$filename"
                    echo "✨ AI-generated task template created!"
                else
                    echo "⚠️  AI generation failed, using default template"
                    use_ai=false
                fi
            fi
        fi

        if [[ "$use_ai" == false ]]; then
            local prev_active2="$(_get_active)"
            if [[ -n "$prev_active2" ]]; then
                _update_status "$prev_active2" "pending"
            fi
            {
                echo "# Task: $task_name"
                echo "Created: $(date)"
                echo "Status: active"
                echo ""
            } > "$filename"
            if [[ "$sections_mode" == true ]]; then
                if ! command -v jq >/dev/null 2>&1; then
                    echo "❌ jq is required for --sections-json/--sections-stdin"
                    echo "   Install with: brew install jq"
                    return 1
                fi
                if ! echo "$sections_json" | jq . >/dev/null 2>&1; then
                    echo "❌ Invalid JSON provided for sections"
                    return 1
                fi
                for key in $(echo "$sections_json" | jq -r 'keys[]'); do
                    echo "## $key" >> "$filename"
                    local vtype=$(echo "$sections_json" | jq -r --arg k "$key" '.[$k] | type')
                    if [[ "$vtype" == "array" ]]; then
                        echo "$sections_json" | jq -r --arg k "$key" '.[$k][]' | while IFS= read -r item; do
                            echo "- [ ] $item" >> "$filename"
                        done
                    else
                        echo "$sections_json" | jq -r --arg k "$key" '.[$k]' >> "$filename"
                    fi
                    echo "" >> "$filename"
                done
            else
                echo "## Description" >> "$filename"
                echo "" >> "$filename"
                echo "## Progress" >> "$filename"
                echo "- [ ] " >> "$filename"
                echo "" >> "$filename"
                echo "## Notes" >> "$filename"
                echo "" >> "$filename"
            fi
            _set_active "$filename"
        fi

        if [[ "$no_open" == false ]]; then
            vim "$filename"
        fi
        return 0
    }

    # Agent invocation hook: Use BGT_AGENT_CMD or ~/.config/bgt-task/agent.zsh
    _invoke_agent() {
        local file="$1"
        export BGT_TASK_FILE="$file"
        export BGT_PROJECT_ROOT="$project_root"
        # Env var hook
        if [[ -n "${BGT_AGENT_CMD-}" ]]; then
            eval "$BGT_AGENT_CMD"
            return $?
        fi
        # Script/function hook
        local agent_hook="$HOME/.config/bgt-task/agent.zsh"
        if [[ -f "$agent_hook" ]]; then
            # shellcheck disable=SC1090
            . "$agent_hook"
            if typeset -f bgt_agent_continue >/dev/null 2>&1; then
                bgt_agent_continue "$file" "$project_root"
                return $?
            fi
        fi
        return 127
    }

    _print_help() {
        echo "bgt - task helper"
        echo ""
        echo "Setup & status:"
        echo "  bgt --setup           Initialize To-Dos and .gitignore in this repo"
        echo "  bgt --status          Show active, latest, and recent tasks"
        echo ""
        echo "Create & switch:"
        echo "  bgt                   Open latest task and set it active"
        echo "  bgt task new <name>   Create a new task (prev active -> pending); combine with -ai/sections"
        echo "  bgt -ai task new <name>  Create AI-prefilled task using terminal context"
        echo "  bgt --sections-json <file>  Use sections JSON for creation (with task new)"
        echo "  bgt --sections-stdin        Read sections JSON from stdin (with task new)"
        echo "  bgt --no-open               Do not open editor after creating/opening"
        echo "  bgt continue          Continue latest task (agent if configured)"
        echo ""
        echo "Task utilities:"
        echo "  bgt task show [frag]  Print active/latest or matching task"
        echo "  bgt task open [frag]  Open active/latest or matching task (sets active)"
        echo "  bgt task continue     Continue latest task (agent if configured)"
        echo "  bgt task select <up|down|top|bottom|index|name>  Select a different task as active"
        echo "  bgt task pending      Mark the active task pending"
        echo "  bgt task complete     Mark the active task complete"
        echo "  bgt task clear        Delete the latest task (with confirmation)"
        echo "  bgt clear             Delete ALL task files (with confirmation)"
    }
    
    # Function to setup the bg environment in the current project
    _setup_bg_environment() {
        echo "🚀 Setting up bg-task in current project..."
        
        # Use the dynamically detected project root
        local todos_dir_here="$project_root/To-Dos"
        
        echo "   Project root: $project_root"
        
        # Create To-Dos directory
        if [[ ! -d "$todos_dir_here" ]]; then
            mkdir -p "$todos_dir_here"
            echo "📁 Created To-Dos directory: $todos_dir_here"
        else
            echo "📁 To-Dos directory already exists"
        fi
        
        # Update .gitignore
        local gitignore_file="$project_root/.gitignore"
        if [[ -f "$gitignore_file" ]]; then
            if ! grep -q "To-Dos/" "$gitignore_file"; then
                echo "" >> "$gitignore_file"
                echo "# To-Dos directory" >> "$gitignore_file"
                echo "To-Dos/" >> "$gitignore_file"
                echo "✅ Added To-Dos/ to .gitignore"
            else
                echo "✅ To-Dos/ already in .gitignore"
            fi
        else
            echo "⚠️  No .gitignore found - you may want to create one"
        fi
        
        # Look for and load .env files
        local env_loaded=false
        local env_files=("$project_root/.env" "$project_root/local.env" "$project_root/.env.local")
        
        for env_file in "${env_files[@]}"; do
            if _load_env_file "$env_file"; then
                env_loaded=true
            fi
        done
        
        if [[ "$env_loaded" == false ]]; then
            echo "ℹ️  No .env files found in project root"
        fi
        
        # Check for ANTHROPIC_API_KEY (safe under set -u)
        if [[ -n "${ANTHROPIC_API_KEY-}" ]]; then
            echo "🤖 Anthropic API key loaded - AI features available!"
        else
            echo "⚠️  ANTHROPIC_API_KEY not found. AI features will be disabled."
            echo "   To enable AI features:"
            echo "   1. Get your API key from: https://console.anthropic.com/"
            echo "   2. Add to your .env file: ANTHROPIC_API_KEY=your-key-here"
            echo "   3. Or export it: export ANTHROPIC_API_KEY='your-key-here'"
        fi
        
        echo ""
        echo "✨ Setup complete for bg-task!"
        echo "Project root: $project_root"
        echo "To-Dos dir:   $todos_dir_here"
        echo ""
        echo "Workflow basics:"
        echo "• Active task pointer: $todos_dir_here/.active"
        echo "• Latest task: newest timestamped *.md in To-Dos/"
        echo "• Switching tasks: previous active is marked 'pending' automatically"
        echo "• Completing a task: sets Status: complete and adds 'Completed: <timestamp>'"
        echo ""
        echo "Commands:"
        echo "  bgt                - Open latest task and set it active"
        echo "  bgt --status       - Show active/latest and recent tasks"
        echo "  bgt -ai task new X - Create AI-prefilled task using terminal context"
        echo "  bgt task new X     - Create a new task"
        echo "  bgt continue       - Continue latest task (set active)"
        echo "  bgt clear          - Delete all task files (with confirmation)"
        echo "  bgt --setup        - Re-run setup here"
        echo "  bgt task select    - Select a different task as active (stack traversal)"
        echo ""
        return 0
    }
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --setup)
                setup_mode=true
                shift
                ;;
            -ai)
                use_ai=true
                shift
                ;;
            --help|-h)
                _print_help
                return 0
                ;;
            --sections-json)
                shift
                sections_mode=true
                sections_json="$(cat "$1" 2>/dev/null)"
                if [[ -z "$sections_json" ]]; then
                    echo "❌ Failed to read sections JSON from file: $1"
                    return 1
                fi
                shift
                ;;
            --sections-stdin)
                sections_mode=true
                sections_json="$(cat -)"
                if [[ -z "$sections_json" ]]; then
                    echo "❌ No JSON received on stdin for --sections-stdin"
                    return 1
                fi
                shift
                ;;
            --no-open)
                no_open=true
                shift
                ;;
            --status|-s)
                if [[ ! -d "$todos_dir" ]]; then
                echo "📁 To-Dos directory doesn't exist. Run 'bgt --setup' first."
                    return 1
                fi
                _print_status
                return 0
                ;;
            task)
                # Subcommands for task management
                shift
                local subcmd="${1:-show}"
                case "$subcmd" in
                    show)
                        if [[ ! -d "$todos_dir" ]]; then
                            echo "📁 To-Dos directory doesn't exist. Run 'bgt --setup' first."
                            return 1
                        fi
                        shift || true
                        local query="$1"
                        local target="$(_get_active)"
                        [[ -z "$target" ]] && target="$(_find_latest_task)"
                        if [[ -n "$query" ]]; then
                            local match=$(_list_tasks_desc | grep "/[^/]*${query}[^/]*\.md$" | head -1)
                            if [[ -n "$match" ]]; then
                                target="$match"
                            fi
                        fi
                        if [[ -n "$target" && -f "$target" ]]; then
                            echo "----- $(basename "$target") -----"
                            cat "$target"
                            return 0
                        else
                            echo "ℹ️  No task file found to show"
                            return 1
                        fi
                        ;;
                    open)
                        if [[ ! -d "$todos_dir" ]]; then
                            echo "📁 To-Dos directory doesn't exist. Run 'bgt --setup' first."
                            return 1
                        fi
                        shift || true
                        local query2="$1"
                        local target2="$(_get_active)"
                        [[ -z "$target2" ]] && target2="$(_find_latest_task)"
                        if [[ -n "$query2" ]]; then
                            local match2=$(_list_tasks_desc | grep "/[^/]*${query2}[^/]*\.md$" | head -1)
                            if [[ -n "$match2" ]]; then
                                target2="$match2"
                            fi
                        fi
                        if [[ -n "$target2" && -f "$target2" ]]; then
                            _set_active "$target2"
                            if [[ "$no_open" == false ]]; then
                                vim "$target2"
                            fi
                            return 0
                        else
                            echo "ℹ️  No task file found to open"
                            return 1
                        fi
                        ;;
                    continue)
                        # Continue latest task within 'task' namespace: set it active; prefer agent
                        if [[ ! -d "$todos_dir" ]]; then
                            echo "📁 To-Dos directory doesn't exist. Run 'bgt --setup' first."
                            return 1
                        fi
                        local latest_tc="$(_find_latest_task)"
                        if [[ -z "$latest_tc" ]]; then
                            echo "ℹ️  No tasks found to continue"
                            return 0
                        fi
                        local prev_tc="$(_get_active)"
                        if [[ -n "$prev_tc" && "$prev_tc" != "$latest_tc" ]]; then
                            _update_status "$prev_tc" "pending"
                        fi
                        _update_status "$latest_tc" "active"
                        _set_active "$latest_tc"
                        if _invoke_agent "$latest_tc"; then
                            return 0
                        fi
                        if [[ "$no_open" == false ]]; then
                            vim "$latest_tc"
                        fi
                        return 0
                        ;;
                    new|create)
                        # Create a new task explicitly: bgt [flags] task new <name>
                        shift || true
                        local new_name="${1:-}"
                        if [[ -z "$new_name" ]]; then
                            echo "Usage: bgt task new <name> [--no-open] [-ai|--sections-json <file>|--sections-stdin]"
                            return 1
                        fi
                        _create_task "$new_name"
                        return $?
                        ;;
                    select)
                        # Select a different task to be active using stack semantics
                        # Usage: bgt task select <up|down|top|bottom|index|name-fragment|filepath>
                        if [[ ! -d "$todos_dir" ]]; then
                            echo "📁 To-Dos directory doesn't exist. Run 'bgt --setup' first."
                            return 1
                        fi
                        # Build ordered stack: newest first
                        local stack_list
                        stack_list=$(_list_tasks_desc)
                        if [[ -z "$stack_list" ]]; then
                            echo "ℹ️  No tasks available to select"
                            return 0
                        fi
                        local -a tasks
                        tasks=(${(f)stack_list})
                        local current="$(_get_active)"
                        # Find current index (1-based)
                        local cur_idx=1
                        local j
                        for (( j=1; j<=${#tasks}; j++ )); do
                            if [[ "${tasks[$j]}" == "$current" ]]; then
                                cur_idx=$j
                                break
                            fi
                        done
                        shift || true
                        local sel="${1:-}"
                        local target_path=""
                        local target_idx=0
                        if [[ -z "$sel" ]]; then
                            echo "Usage: bgt task select <up|down|top|bottom|index|name-fragment|filepath>"
                            echo "Current: $cur_idx/${#tasks} -> $(basename "$current")"
                            return 1
                        fi
                        case "$sel" in
                            up)
                                target_idx=$(( cur_idx + 1 ))
                                ;;
                            down)
                                target_idx=$(( cur_idx - 1 ))
                                ;;
                            top)
                                target_idx=1
                                ;;
                            bottom)
                                target_idx=${#tasks}
                                ;;
                            *)
                                if [[ "$sel" =~ ^[0-9]+$ ]]; then
                                    target_idx=$sel
                                else
                                    # Treat as filepath, exact basename, or name fragment
                                    if [[ -f "$sel" ]]; then
                                        target_path="$sel"
                                    else
                                        if [[ "$sel" == *.md ]]; then
                                            local match_exact
                                            match_exact=$(_list_tasks_desc | awk -F'/' -v b="$sel" '{if ($NF==b){print; exit}}')
                                            if [[ -n "$match_exact" ]]; then
                                                target_path="$match_exact"
                                            fi
                                        else
                                            local match
                                            match=$(_list_tasks_desc | grep "/[^/]*${sel}[^/]*\\.md$" | head -1)
                                            if [[ -n "$match" ]]; then
                                                target_path="$match"
                                            fi
                                        fi
                                    fi
                                fi
                                ;;
                        esac
                        if [[ $target_idx -gt 0 ]]; then
                            if (( target_idx < 1 || target_idx > ${#tasks} )); then
                                echo "❌ Index out of range: $target_idx (1..${#tasks})"
                                return 1
                            fi
                            target_path="${tasks[$target_idx]}"
                        fi
                        if [[ -z "$target_path" ]]; then
                            echo "❌ No matching task found for: $sel"
                            return 1
                        fi
                        if [[ "$target_path" == "$current" ]]; then
                            echo "ℹ️  Already active: $(basename "$current")"
                            return 0
                        fi
                        # Update statuses and active pointer
                        if [[ -n "$current" ]]; then
                            _update_status "$current" "pending"
                        fi
                        _update_status "$target_path" "active"
                        _set_active "$target_path"
                        echo "➡️  Active now: $(basename "$target_path")"
                        if [[ "$no_open" == false ]]; then
                            vim "$target_path"
                        fi
                        return 0
                        ;;
                    pending)
                        if [[ ! -d "$todos_dir" ]]; then
                        echo "📁 To-Dos directory doesn't exist. Run 'bgt --setup' first."
                            return 1
                        fi
                        local tgtp="$(_get_active)"
                        if [[ -z "$tgtp" ]]; then
                            echo "ℹ️  No active task to mark pending"
                            return 0
                        fi
                        _update_status "$tgtp" "pending"
                        echo "⏸️  Marked pending: $(basename "$tgtp")"
                        return 0
                        ;;
                    complete)
                        if [[ ! -d "$todos_dir" ]]; then
                        echo "📁 To-Dos directory doesn't exist. Run 'bgt --setup' first."
                            return 1
                        fi
                        local tgtc="$(_get_active)"
                        if [[ -z "$tgtc" ]]; then
                            echo "ℹ️  No active task to complete"
                            return 0
                        fi
                        _update_status "$tgtc" "complete"
                        echo "✅ Marked complete: $(basename "$tgtc")"
                        return 0
                        ;;
                    clear)
                        if [[ ! -d "$todos_dir" ]]; then
                        echo "📁 To-Dos directory doesn't exist. Run 'bgt --setup' first."
                            return 1
                        fi
                        local latest="$(_find_latest_task)"
                        if [[ -z "$latest" ]]; then
                            echo "ℹ️  No task files to delete"
                            return 0
                        fi
                        echo "⚠️  This will delete the latest task: $(basename "$latest")"
                        echo -n "Proceed? (y/N): "
                        read -r resp
                        if [[ "$resp" =~ ^[Yy]$ ]]; then
                            local active_file="$(_get_active)"
                            rm -f "$latest"
                            echo "🗑️  Deleted: $(basename "$latest")"
                            if [[ "$active_file" == "$latest" ]]; then
                                local new_latest="$(_find_latest_task)"
                                if [[ -n "$new_latest" ]]; then
                                    _set_active "$new_latest"
                                    echo "➡️  Active now: $(basename "$new_latest")"
                                else
                                    rm -f "$(_active_pointer_file)" 2>/dev/null
                                    echo "ℹ️  No tasks remain. Active pointer cleared."
                                fi
                            fi
                        else
                            echo "❌ Operation cancelled"
                        fi
                        return 0
                        ;;
                    *)
                        echo "❌ Unknown 'task' subcommand: $subcmd"
                        echo "Usage: bgt task show [name-fragment]"
                        return 1
                        ;;
                esac
                ;;
            continue)
                # Continue working on the latest task: set it active; prefer agent
                if [[ ! -d "$todos_dir" ]]; then
                    echo "📁 To-Dos directory doesn't exist. Run 'bgt --setup' first."
                    return 1
                fi
                local latest_c="$(_find_latest_task)"
                if [[ -z "$latest_c" ]]; then
                    echo "ℹ️  No tasks found to continue"
                    return 0
                fi
                local prev_c="$(_get_active)"
                if [[ -n "$prev_c" && "$prev_c" != "$latest_c" ]]; then
                    _update_status "$prev_c" "pending"
                fi
                _update_status "$latest_c" "active"
                _set_active "$latest_c"
                if _invoke_agent "$latest_c"; then
                    return 0
                fi
                if [[ "$no_open" == false ]]; then
                    vim "$latest_c"
                fi
                return 0
                ;;
            clear)
                # Handle 'clear' command
                local file_count=$(find "$todos_dir" -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
                
                if [[ $file_count -eq 0 ]]; then
                    echo "📁 To-Dos directory is already empty!"
                    return 0
                fi
                
                echo "⚠️  This will delete $file_count task file(s) from your To-Dos directory:"
                find "$todos_dir" -name "*.md" -type f -exec basename {} \; 2>/dev/null
                echo ""
                echo -n "Are you sure you want to delete all task files? (y/N): "
                read -r response
                
                if [[ "$response" =~ ^[Yy]$ ]]; then
                    rm -f "$todos_dir"/*.md 2>/dev/null
                    echo "🗑️  All task files have been deleted from To-Dos directory"
                else
                    echo "❌ Operation cancelled - no files were deleted"
                fi
                return 0
                ;;
            -*)
                echo "❌ Unknown flag: $1"
                echo "Usage: bgt [--setup] [-ai] [taskname|continue|clear]"
                return 1
                ;;
            *)
                echo "❌ Unknown command or argument: $1"
                echo "Try: bgt --help"
                return 1
                ;;
        esac
    done
    
    # Handle setup mode
    if [[ "$setup_mode" == true ]]; then
        _setup_bg_environment
        return 0
    fi
    
    # Ensure To-Dos directory exists
    if [[ ! -d "$todos_dir" ]]; then
        echo "📁 To-Dos directory doesn't exist. Run 'bgt --setup' first."
        return 1
    fi
    
    # Auto-load .env files if available and not already loaded (safe under set -u)
    if [[ -z "${ANTHROPIC_API_KEY-}" && "$use_ai" == true ]]; then
        local env_files=("$project_root/.env" "$project_root/local.env" "$project_root/.env.local")
        for env_file in "${env_files[@]}"; do
            _load_env_file "$env_file" >/dev/null
        done
    fi
    
    # If sections were provided, disable AI path
    if [[ "$sections_mode" == true ]]; then
        use_ai=false
    fi

    # If no args led to an action, open latest or create a default initial task
    local latest_file="$(_find_latest_task)"
    if [[ -n "$latest_file" ]]; then
        _set_active "$latest_file"
        if [[ "$no_open" == false ]]; then
            vim "$latest_file"
        fi
        return 0
    else
        _create_task "task"
        return $?
    fi
}

# Alias for the function
alias begin='bgt'
