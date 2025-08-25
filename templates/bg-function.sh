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
    local task_name=""
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
        ls -1t "$todos_dir"/*.md 2>/dev/null | head -1
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
        ls -1t "$todos_dir"/*.md 2>/dev/null | head -5 | while read -r f; do
            local st=$(grep -m1 '^Status:' "$f" 2>/dev/null | awk -F': ' '{print $2}')
            [[ -z "$st" ]] && st="unknown"
            echo "  - $(basename "$f") [${st}]"
        done
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
        echo "  bgt <name>            Create/switch to <name> and set active (prev -> pending)"
        echo "  bgt -ai <name>        Create AI-prefilled task using terminal context"
        echo "  bgt --sections-json <file>  Create using sections JSON (skips AI)"
        echo "  bgt --sections-stdin        Read sections JSON from stdin (skips AI)"
        echo "  bgt --no-open               Do not open editor after creating/opening"
        echo "  bgt continue          Continue latest task (set active)"
        echo ""
        echo "Task utilities:"
        echo "  bgt task show [frag]  Print active/latest or matching task"
        echo "  bgt task open [frag]  Open active/latest or matching task (sets active)"
        echo "  bgt task continue     Continue latest task (sets active)"
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
        echo "  bgt taskname       - Create/switch to a task and set it active"
        echo "  bgt                - Open latest task and set it active"
        echo "  bgt --status       - Show active/latest and recent tasks"
        echo "  bgt -ai taskname   - Create AI-prefilled task using terminal context"
        echo "  bgt continue       - Continue latest task (set active)"
        echo "  bgt clear          - Delete all task files (with confirmation)"
        echo "  bgt --setup        - Re-run setup here"
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
                            local match=$(ls -1t "$todos_dir"/*.md 2>/dev/null | grep "/[^/]*${query}[^/]*\.md$" | head -1)
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
                            local match2=$(ls -1t "$todos_dir"/*.md 2>/dev/null | grep "/[^/]*${query2}[^/]*\.md$" | head -1)
                            if [[ -n "$match2" ]]; then
                                target2="$match2"
                            fi
                        fi
                        if [[ -n "$target2" && -f "$target2" ]]; then
                            _set_active "$target2"
                            vim "$target2"
                            return 0
                        else
                            echo "ℹ️  No task file found to open"
                            return 1
                        fi
                        ;;
                    continue)
                        # Continue latest task within 'task' namespace: set it active, mark previous pending, open it
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
                        vim "$latest_tc"
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
                # Continue working on the latest task: set it active, mark previous active pending, open it
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
                vim "$latest_c"
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
                task_name="$1"
                shift
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

    # If no task name provided, open latest or create a default
    if [[ -z "$task_name" ]]; then
        local latest_file="$(_find_latest_task)"
        if [[ -n "$latest_file" ]]; then
            _set_active "$latest_file"
            if [[ "$no_open" == false ]]; then
                vim "$latest_file"
            fi
            return 0
        else
            task_name="task"
        fi
    fi
    
    # If a name is provided, create a new task when it's not the latest
    local latest_file="$(_find_latest_task)"
    if [[ -n "$latest_file" ]]; then
        if echo "$latest_file" | grep -q "_${task_name}\.md$"; then
            # Same as latest; just open and set active
            _set_active "$latest_file"
            if [[ "$no_open" == false ]]; then
                vim "$latest_file"
            fi
            return 0
        fi
        # Different task requested; mark current active pending
        local current_active="$(_get_active)"
        if [[ -n "$current_active" && "$current_active" != "$latest_file" ]]; then
            _update_status "$current_active" "pending"
        fi
    fi
    
    local timestamp=$(date +"%Y-%m-%d_%H-%M-%S")
    local filename="$todos_dir/${timestamp}_${task_name}.md"
    
    if [[ "$use_ai" == true ]]; then
        echo "🤖 Generating AI-powered task template..."
        # Capture current active to mark pending after successful creation
        local prev_active="$(_get_active)"
        
        # Check if API key is available (safe under set -u)
        if [[ -z "${ANTHROPIC_API_KEY-}" ]]; then
            echo "⚠️  ANTHROPIC_API_KEY not found. Using default template."
            echo "   Run 'bgt --setup' for setup instructions."
            use_ai=false
        fi
    fi
    
    if [[ "$use_ai" == true ]]; then
        # Get recent terminal history (last 20 commands, excluding bg commands)
        local history_context=""
        history_context=$(fc -ln -50 2>/dev/null | grep -v ' bgt ' | tail -20)
        if [[ -z "$history_context" && -r ${HISTFILE:-$HOME/.zsh_history} ]]; then
            history_context=$(tail -n 50 "${HISTFILE:-$HOME/.zsh_history}" 2>/dev/null | sed 's/^: [0-9]*:[0-9]*;//' | grep -v ' bgt ' | tail -20)
        fi
        local current_dir=$(pwd)
        local git_status=""
        
        # Try to get git context if we're in a git repo
        if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            git_status=$(git status --porcelain 2>/dev/null | head -10)
        fi
        
        # Create AI prompt
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
        
        # Call Claude API
        local ai_response=$(curl -s -X POST https://api.anthropic.com/v1/messages \
            -H "Content-Type: application/json" \
            -H "x-api-key: $ANTHROPIC_API_KEY" \
            -H "anthropic-version: 2023-06-01" \
            -d "{\"model\": \"claude-3-5-sonnet-20241022\", \"max_tokens\": 1000, \"messages\": [{ \"role\": \"user\", \"content\": $(echo "$ai_prompt" | jq -Rs .)}]}" 2>/dev/null | jq -r '.content[0].text' 2>/dev/null)
        
        if [[ -n "$ai_response" && "$ai_response" != "null" && "$ai_response" != "" ]]; then
            echo "$ai_response" > "$filename"
            # Ensure Status line exists and is active
            if ! grep -q '^Status:' "$filename" 2>/dev/null; then
                awk 'NR==1{print;next} NR==2{print; print "Status: active"; next} {print}' "$filename" > "$filename.tmp" && mv "$filename.tmp" "$filename"
            else
                _update_status "$filename" "active"
            fi
            # Mark previous active pending and set new active
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
    
    # Fallback to default template if AI didn't work or wasn't used
    if [[ "$use_ai" == false ]]; then
        # Mark previous active pending (before creating the new file)
        local prev_active2="$(_get_active)"
        if [[ -n "$prev_active2" ]]; then
            _update_status "$prev_active2" "pending"
        fi
        # Create the new task file with active status and body
        {
            echo "# Task: $task_name"
            echo "Created: $(date)"
            echo "Status: active"
            echo ""
        } > "$filename"

        if [[ "$sections_mode" == true ]]; then
            # Require jq for JSON parsing
            if ! command -v jq >/dev/null 2>&1; then
                echo "❌ jq is required for --sections-json/--sections-stdin"
                echo "   Install with: brew install jq"
                return 1
            fi
            # Validate JSON
            if ! echo "$sections_json" | jq . >/dev/null 2>&1; then
                echo "❌ Invalid JSON provided for sections"
                return 1
            fi
            # Render sections dynamically
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
    
    # Open in vim unless suppressed
    if [[ "$no_open" == false ]]; then
        vim "$filename"
    fi
}

# Alias for the function
alias begin='bgt'
