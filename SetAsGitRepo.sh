#!/bin/bash

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly GENERAL_IGNORE=".env *.log .DS_Store .vscode .idea"

# Project-specific .gitignore templates
declare -A PROJECT_TEMPLATES=(
    ["node"]="node_modules/ npm-debug.log* yarn-debug.log* yarn-error.log* .npm .yarn-integrity .pnpm-debug.log* dist/ build/ coverage/"
    ["python"]="__pycache__/ *.py[cod] *$py.class *.so .Python build/ develop-eggs/ dist/ downloads/ eggs/ .eggs/ lib/ lib64/ parts/ sdist/ var/ wheels/ *.egg-info/ .installed.cfg *.egg .env .venv env/ venv/ ENV/ env.bak/ venv.bak/ .pytest_cache/ .coverage htmlcov/ .tox/ .cache .mypy_cache/ .dmypy.json dmypy.json"
    ["java"]="*.class *.jar *.war *.ear *.zip *.tar.gz *.rar target/ build/ .gradle/ gradle-app.setting !gradle-wrapper.jar .gradletasknamecache .settings/ .project .classpath bin/ tmp/ *.tmp *.bak *.swp *~.nib local.properties .loadpath .factorypath"
    ["csharp"]="bin/ obj/ *.user *.suo *.cache *.pdb *.exe *.dll *.manifest *.application *.clickonce packages/ .vs/ *.log *.vspscc *.vssscc .builds *.pidb *.svclog *.scc"
    ["go"]="*.exe *.exe~ *.dll *.so *.dylib *.test *.out go.work vendor/ .vscode/ .idea/"
    ["rust"]="target/ Cargo.lock *.rs.bk *.pdb"
    ["php"]="vendor/ composer.phar .env .env.local .env.*.local *.log /storage/logs/ /bootstrap/cache/ .phpunit.result.cache"
    ["ruby"]="*.gem *.rbc /.config .yardoc/ _yardoc/ doc/ rdoc/ .bundle/ vendor/bundle/ lib/bundler/man/ tmp/ .sass-cache/ .rvmrc Gemfile.lock"
    ["react"]="node_modules/ npm-debug.log* yarn-debug.log* yarn-error.log* .npm .yarn-integrity .pnpm-debug.log* build/ dist/ .env .env.local .env.development.local .env.test.local .env.production.local coverage/"
    ["vue"]="node_modules/ npm-debug.log* yarn-debug.log* yarn-error.log* .npm .yarn-integrity .pnpm-debug.log* dist/ coverage/ .env .env.local .env.*.local"
    ["angular"]="node_modules/ npm-debug.log* yarn-debug.log* yarn-error.log* .npm .yarn-integrity .pnpm-debug.log* dist/ coverage/ .angular/ .env .env.local .env.*.local"
    ["flutter"]="*.iml *.ipr *.iws .idea/ .gradle/ local.properties .pub-cache/ .pub/ build/ .flutter-plugins .flutter-plugins-dependencies .packages .pub-cache/ .pub/ ios/.symlinks/ .fvm/"
    ["unity"]="Library/ Temp/ Obj/ Build/ Builds/ Logs/ UserSettings/ .vsconfig *.tmp *.user *.userprefs *.pidb *.booproj *.svd *.pdb *.mdb *.opendb *.VC.db sysinfo.txt *.stackdump"
)

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Global variables for learning mode
EXPLAIN_MODE=false
PROJECT_TYPE=""
GENERATE_TUTORIAL=false

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_explain() { [[ "$EXPLAIN_MODE" == "true" ]] && echo -e "${PURPLE}[EXPLAIN]${NC} $1"; }
log_command() { [[ "$EXPLAIN_MODE" == "true" ]] && echo -e "${CYAN}[COMMAND]${NC} $1"; }

# Help function
show_help() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS] [DIRECTORY]

Initialize a Git repository with .gitignore setup and optional remote configuration.

Arguments:
    DIRECTORY    Target directory (default: current directory)

Options:
    -h, --help     Show this help message
    -e, --explain  Enable command explanation mode (educational)
    -t, --tutorial Generate post-setup tutorial and cheat sheet

Examples:
    $SCRIPT_NAME                           # Initialize in current directory
    $SCRIPT_NAME --explain                 # Initialize with explanations
    $SCRIPT_NAME --tutorial /path/project  # Initialize with tutorial
    $SCRIPT_NAME -e -t                     # Full learning mode
EOF
}

# Parse command line arguments
parse_args() {
    local directory="."
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -e|--explain)
                EXPLAIN_MODE=true
                shift
                ;;
            -t|--tutorial)
                GENERATE_TUTORIAL=true
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
            *)
                directory="$1"
                shift
                ;;
        esac
    done
    
    echo "$directory"
}

# Execute command with explanation
execute_with_explanation() {
    local command="$1"
    local explanation="$2"
    local show_output="${3:-true}"
    
    log_explain "$explanation"
    log_command "Running: $command"
    
    if [[ "$show_output" == "true" ]]; then
        eval "$command"
    else
        eval "$command" >/dev/null 2>&1
    fi
    
    local exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        log_explain "✓ Command completed successfully"
    else
        log_error "Command failed with exit code $exit_code"
        return $exit_code
    fi
    
    [[ "$EXPLAIN_MODE" == "true" ]] && echo
    return 0
}

# Check system requirements
check_requirements() {
    local missing_deps=()
    
    if ! command -v git &> /dev/null; then
        missing_deps+=("git")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        log_error "Please install missing dependencies and try again."
        exit 1
    fi
    
    # Check for optional dependencies
    if command -v secret-tool &> /dev/null; then
        log_info "Found secret-tool - credential storage available"
        return 0
    else
        log_warning "secret-tool not found - credentials won't be stored"
        log_info "To enable credential storage: sudo apt-get install libsecret-tools"
        return 1
    fi
}

# Validate directory
validate_directory() {
    local dir="$1"
    
    if [[ ! -d "$dir" ]]; then
        log_error "Directory '$dir' does not exist"
        exit 1
    fi
    
    if [[ -d "$dir/.git" ]]; then
        log_error "Directory '$dir' is already a Git repository"
        exit 1
    fi
    
    # Check if directory is writable
    if [[ ! -w "$dir" ]]; then
        log_error "Directory '$dir' is not writable"
        exit 1
    fi
}

# Configure Git credential helper
configure_git_credentials() {
    local has_secret_tool="$1"
    
    if [[ "$has_secret_tool" == "0" ]]; then
        # Try to set up libsecret if available
        if execute_with_explanation \
            "git config --global credential.helper libsecret" \
            "Configuring Git to use secure credential storage (libsecret helper)" \
            false; then
            log_success "Configured Git to use libsecret credential helper"
        else
            log_warning "Could not configure libsecret credential helper"
        fi
    fi
}

# Detect project type based on files in directory
detect_project_type() {
    local -a detected_types=()
    
    # Check for various project indicators
    [[ -f "package.json" ]] && {
        if grep -q '"react"' package.json 2>/dev/null; then
            detected_types+=("react")
        elif grep -q '"vue"' package.json 2>/dev/null; then
            detected_types+=("vue")
        elif grep -q '"@angular"' package.json 2>/dev/null; then
            detected_types+=("angular")
        else
            detected_types+=("node")
        fi
    }
    
    [[ -f "requirements.txt" || -f "setup.py" || -f "pyproject.toml" || -f "Pipfile" ]] && detected_types+=("python")
    [[ -f "pom.xml" || -f "build.gradle" || -f "build.gradle.kts" ]] && detected_types+=("java")
    [[ -f "*.csproj" || -f "*.sln" || -f "global.json" ]] && detected_types+=("csharp")
    [[ -f "go.mod" || -f "go.sum" ]] && detected_types+=("go")
    [[ -f "Cargo.toml" ]] && detected_types+=("rust")
    [[ -f "composer.json" ]] && detected_types+=("php")
    [[ -f "Gemfile" ]] && detected_types+=("ruby")
    [[ -f "pubspec.yaml" ]] && detected_types+=("flutter")
    [[ -f "Assets/" && -d "ProjectSettings/" ]] && detected_types+=("unity")
    
    printf "%s\n" "${detected_types[@]}"
}

# Display available project types
show_project_types() {
    echo "Available project types:"
    echo "  node     - Node.js/JavaScript projects"
    echo "  react    - React applications"
    echo "  vue      - Vue.js applications" 
    echo "  angular  - Angular applications"
    echo "  python   - Python projects"
    echo "  java     - Java/Maven/Gradle projects"
    echo "  csharp   - C#/.NET projects"
    echo "  go       - Go projects"
    echo "  rust     - Rust projects"
    echo "  php      - PHP projects"
    echo "  ruby     - Ruby projects"
    echo "  flutter  - Flutter/Dart projects"
    echo "  unity    - Unity game engine projects"
}

# Get .gitignore entries for project type
get_project_gitignore() {
    local project_type="$1"
    
    if [[ -n "${PROJECT_TEMPLATES[$project_type]:-}" ]]; then
        echo "${PROJECT_TEMPLATES[$project_type]}"
    else
        return 1
    fi
}

is_valid_gitignore_entry() {
    local entry="$1"
    
    # Check if entry is non-empty and doesn't contain dangerous characters
    [[ -n "$entry" ]] && [[ ! "$entry" =~ [<>|] ]] && [[ "$entry" != *"/"* || "$entry" == *"/" ]]
}

# Setup .gitignore
setup_gitignore() {
    echo
    log_info "Setting up .gitignore file..."
    log_explain "The .gitignore file tells Git which files and directories to ignore when tracking changes."
    
    if [[ ! -f ".gitignore" ]]; then
        execute_with_explanation \
            "touch .gitignore" \
            "Creating a new .gitignore file using 'touch' command" \
            false
        log_success "Created new .gitignore file"
    else
        log_info "Using existing .gitignore file"
        log_explain "Found existing .gitignore - we'll add to it without overwriting existing rules"
    fi
    
    # Detect project types
    local -a detected_types
    mapfile -t detected_types < <(detect_project_type)
    
    local project_entries=""
    local recommended_type=""
    
    if [[ ${#detected_types[@]} -gt 0 ]]; then
        echo
        log_success "Detected project type(s): ${detected_types[*]}"
        log_explain "Project type detection looks for specific files like package.json, requirements.txt, etc."
        recommended_type="${detected_types[0]}"  # Use first detected type as primary
        PROJECT_TYPE="$recommended_type"  # Store for tutorial generation
        
        # Get entries for detected project type
        if project_entries=$(get_project_gitignore "$recommended_type"); then
            log_info "Recommended .gitignore entries for $recommended_type project:"
            echo "$project_entries" | tr ' ' '\n' | sed 's/^/  /'
        fi
    else
        echo
        log_info "No specific project type detected"
        log_explain "Without specific files detected, I'll show you all available project types"
        show_project_types
        echo
        read -p "Enter project type for recommendations (or press Enter to skip): " recommended_type
        
        if [[ -n "$recommended_type" ]] && project_entries=$(get_project_gitignore "$recommended_type"); then
            PROJECT_TYPE="$recommended_type"
            echo
            log_info "Recommended .gitignore entries for $recommended_type:"
            echo "$project_entries" | tr ' ' '\n' | sed 's/^/  /'
        elif [[ -n "$recommended_type" ]]; then
            log_warning "Unknown project type: $recommended_type"
            recommended_type=""
        fi
    fi
    
    # Build the proposed ignore list
    local proposed_entries="$GENERAL_IGNORE"
    if [[ -n "$project_entries" ]]; then
        proposed_entries="$proposed_entries $project_entries"
    fi
    
    echo
    if [[ -n "$recommended_type" ]]; then
        echo "Proposed entries (general + $recommended_type):"
    else
        echo "Proposed entries (general only):"
    fi
    echo "$proposed_entries" | tr ' ' '\n' | sed 's/^/  /'
    
    log_explain "General entries protect against common files like .env (secrets), .DS_Store (macOS), and IDE configs"
    
    echo
    echo "Options:"
    echo "  [Enter] - Accept proposed entries"
    echo "  'custom' - Enter your own entries"
    echo "  'add' - Accept proposed + add custom entries"
    echo "  'skip' - Skip .gitignore setup"
    
    local user_choice=""
    read -p "Choice: " user_choice
    
    local final_entries=""
    
    case "$user_choice" in
        ""|"accept")
            final_entries="$proposed_entries"
            log_info "Using proposed .gitignore entries"
            ;;
        "custom")
            read -p "Enter custom entries (space-separated): " final_entries
            log_info "Using custom .gitignore entries"
            ;;
        "add")
            local additional_entries=""
            read -p "Enter additional entries (space-separated): " additional_entries
            final_entries="$proposed_entries $additional_entries"
            log_info "Using proposed + additional .gitignore entries"
            ;;
        "skip")
            log_info "Skipping .gitignore setup"
            return 0
            ;;
        *)
            log_warning "Invalid choice, using proposed entries"
            final_entries="$proposed_entries"
            ;;
    esac
    
    # Process and add entries
    if [[ -n "$final_entries" ]]; then
        local -a valid_entries=()
        read -ra entries <<< "$final_entries"
        
        for entry in "${entries[@]}"; do
            if is_valid_gitignore_entry "$entry"; then
                if ! grep -Fxq "$entry" .gitignore 2>/dev/null; then
                    valid_entries+=("$entry")
                else
                    log_warning "Skipping duplicate entry: $entry"
                fi
            else
                log_warning "Skipping invalid entry: $entry"
            fi
        done
        
        # Add valid entries
        if [[ ${#valid_entries[@]} -gt 0 ]]; then
            log_explain "Adding entries to .gitignore using printf to append each entry on a new line"
            printf "%s\n" "${valid_entries[@]}" >> .gitignore
            log_success "Added ${#valid_entries[@]} entries to .gitignore"
            
            # Show final .gitignore content
            echo
            log_info "Final .gitignore content:"
            cat .gitignore | sed 's/^/  /'
        else
            log_warning "No valid entries to add"
        fi
    fi
}

# Validate URL format
is_valid_git_url() {
    local url="$1"
    
    # Check for common Git URL patterns
    [[ "$url" =~ ^https?://[^/]+/.+\.git$ ]] || \
    [[ "$url" =~ ^git@[^:]+:.+\.git$ ]] || \
    [[ "$url" =~ ^ssh://git@[^/]+/.+\.git$ ]]
}

# Extract hostname from URL
extract_hostname() {
    local url="$1"
    
    if [[ "$url" =~ ^https?://([^/]+) ]]; then
        echo "${BASH_REMATCH[1]}"
    elif [[ "$url" =~ ^git@([^:]+): ]]; then
        echo "${BASH_REMATCH[1]}"
    elif [[ "$url" =~ ^ssh://git@([^/]+) ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        return 1
    fi
}

# Store credentials securely
store_credentials() {
    local host="$1"
    local username="$2"
    local token="$3"
    
    if command -v secret-tool &> /dev/null; then
        log_explain "Storing credentials securely in system keyring using secret-tool"
        # Store username and token separately
        if secret-tool store --label="Git username for $host" git-user "$host" <<< "$username" && \
           secret-tool store --label="Git token for $host" git-token "$host" <<< "$token"; then
            log_success "Stored credentials for $host in keyring"
            return 0
        else
            log_warning "Failed to store credentials in keyring"
            return 1
        fi
    else
        log_warning "Cannot store credentials - secret-tool not available"
        return 1
    fi
}

# Retrieve stored credentials
get_stored_credentials() {
    local host="$1"
    local username=""
    local token=""
    
    if command -v secret-tool &> /dev/null; then
        username=$(secret-tool lookup git-user "$host" 2>/dev/null || echo "")
        token=$(secret-tool lookup git-token "$host" 2>/dev/null || echo "")
        
        if [[ -n "$username" && -n "$token" ]]; then
            echo "$username:$token"
            return 0
        fi
    fi
    
    return 1
}

# Get credentials from user
prompt_credentials() {
    local host="$1"
    local username=""
    local token=""
    
    echo
    log_info "Enter credentials for $host:"
    log_explain "Personal access tokens are recommended over passwords for Git hosting services"
    read -p "Username: " username
    read -s -p "Token/Password: " token
    echo
    
    if [[ -z "$username" || -z "$token" ]]; then
        log_error "Username and token are required"
        return 1
    fi
    
    echo "$username:$token"
}

# Prompt for branch name
prompt_branch_name() {
    local branch_name=""
    
    echo
    log_info "Setting up initial branch..."
    log_explain "The default branch is where your main development happens. 'main' is the modern standard."
    read -p "Enter initial branch name (default: main): " branch_name
    
    # Use 'main' as default if nothing specified
    branch_name="${branch_name:-main}"
    
    # Validate branch name
    if ! [[ "$branch_name" =~ ^[a-zA-Z0-9._/-]+$ ]] || [[ "$branch_name" =~ ^[.-] ]] || [[ "$branch_name" == *".."* ]]; then
        log_error "Invalid branch name: $branch_name"
        log_error "Branch names cannot start with . or -, and cannot contain consecutive dots"
        return 1
    fi
    
    echo "$branch_name"
}

# Setup remote repository
setup_remote() {
    local branch_name="$1"
    local remote_url=""
    
    echo
    log_explain "A remote repository is a version of your project hosted on a service like GitHub, GitLab, etc."
    read -p "Enter remote repository URL (or press Enter to skip): " remote_url
    
    if [[ -z "$remote_url" ]]; then
        log_info "No remote repository configured"
        log_explain "You can add a remote later with: git remote add origin <URL>"
        return 0
    fi
    
    if ! is_valid_git_url "$remote_url"; then
        log_error "Invalid Git repository URL format"
        log_error "Expected formats: https://github.com/user/repo.git or git@github.com:user/repo.git"
        return 1
    fi
    
    local host
    if ! host=$(extract_hostname "$remote_url"); then
        log_error "Could not extract hostname from URL"
        return 1
    fi
    
    log_info "Adding remote repository: $remote_url"
    execute_with_explanation \
        "git remote add origin \"$remote_url\"" \
        "Adding remote repository as 'origin' - this creates a link to your hosted repository"
    
    # Handle credentials
    local credentials=""
    local username=""
    local token=""
    
    # Try to get stored credentials first
    if credentials=$(get_stored_credentials "$host"); then
        log_success "Using stored credentials for $host"
        username="${credentials%%:*}"
        token="${credentials##*:}"
    else
        # Prompt for new credentials
        if ! credentials=$(prompt_credentials "$host"); then
            return 1
        fi
        username="${credentials%%:*}"
        token="${credentials##*:}"
        
        # Store credentials if possible
        store_credentials "$host" "$username" "$token"
    fi
    
    log_info "Pushing to remote repository (branch: $branch_name)..."
    log_explain "This uploads your initial commit to the remote repository and sets up tracking"
    
    # Use credential helper approach instead of environment variables
    if execute_with_explanation \
        "git -c credential.helper='!f() { echo \"username=$username\"; echo \"password=$token\"; }; f' push -u origin \"$branch_name\"" \
        "Pushing local commits to remote and setting up branch tracking with -u flag" \
        false; then
        log_success "Successfully pushed to remote repository"
        log_explain "The -u flag sets up tracking so future 'git push' commands know where to push"
    else
        log_error "Failed to push to remote repository"
        log_error "Please check your credentials and repository access"
        return 1
    fi
}

# Generate Git workflow cheat sheet
generate_cheat_sheet() {
    local project_type="$1"
    local branch_name="$2"
    local cheat_sheet_file="GIT_CHEATSHEET.md"
    
    log_info "Generating Git workflow cheat sheet..."
    
    cat > "$cheat_sheet_file" << EOF
# Git Workflow Cheat Sheet
*Generated for your $project_type project*

## Daily Workflow Commands

### Check Status
\`\`\`bash
git status                    # See what files have changed
git log --oneline -10         # View recent commits
git diff                      # See unstaged changes
git diff --staged             # See staged changes
\`\`\`

### Making Changes
\`\`\`bash
git add <filename>            # Stage specific file
git add .                     # Stage all changes
git commit -m "message"       # Commit with message
git push                      # Push to remote (after initial setup)
\`\`\`

### Branch Management
\`\`\`bash
git branch                    # List local branches
git branch <name>             # Create new branch
git checkout <name>           # Switch to branch
git checkout -b <name>        # Create and switch to new branch
git merge <branch>            # Merge branch into current
git branch -d <name>          # Delete branch (safe)
\`\`\`

### Remote Operations
\`\`\`bash
git pull                      # Fetch and merge from remote
git fetch                     # Fetch without merging
git push origin <branch>      # Push specific branch
git clone <url>               # Clone repository
\`\`\`

### Fixing Mistakes
\`\`\`bash
git checkout -- <file>       # Discard unstaged changes
git reset HEAD <file>        # Unstage file
git reset --soft HEAD^       # Undo last commit (keep changes)
git reset --hard HEAD^       # Undo last commit (lose changes)
\`\`\`

EOF

    # Add project-specific commands
    case "$project_type" in
        "node"|"react"|"vue"|"angular")
            cat >> "$cheat_sheet_file" << EOF
## $project_type Specific Tips

### Before Committing
\`\`\`bash
npm run lint                  # Check code style
npm run test                  # Run tests
npm run build                 # Verify build works
\`\`\`

### Common Ignore Patterns Already Set
- node_modules/ (dependencies)
- dist/, build/ (built assets)
- .env files (secrets)
- Coverage reports

EOF
            ;;
        "python")
            cat >> "$cheat_sheet_file" << EOF
## Python Specific Tips

### Before Committing
\`\`\`bash
python -m pytest             # Run tests
black .                       # Format code
flake8                        # Check style
\`\`\`

### Virtual Environment
\`\`\`bash
python -m venv venv           # Create virtual environment
source venv/bin/activate      # Activate (Linux/Mac)
venv\\Scripts\\activate        # Activate (Windows)
\`\`\`

### Common Ignore Patterns Already Set
- __pycache__/ (compiled Python)
- *.pyc (bytecode files)
- .env, venv/ (environment files)
- .pytest_cache/ (test cache)

EOF
            ;;
        "java")
            cat >> "$cheat_sheet_file" << EOF
## Java Specific Tips

### Before Committing
\`\`\`bash
mvn clean test                # Maven: clean and test
gradle clean test             # Gradle: clean and test
mvn clean compile             # Maven: verify compilation
\`\`\`

### Common Ignore Patterns Already Set
- target/ (Maven builds)
- build/ (Gradle builds)
- *.class (compiled Java)
- .gradle/ (Gradle cache)

EOF
            ;;
    esac

    cat >> "$cheat_sheet_file" << EOF
## Your Project Setup

- **Main Branch**: $branch_name
- **Project Type**: $project_type
- **Remote**: $(git remote get-url origin 2>/dev/null || echo "Not configured")

## Recommended Commit Message Format
\`\`\`
type: brief description

Longer explanation if needed

Examples:
feat: add user authentication
fix: resolve login validation bug
docs: update API documentation
style: fix code formatting
refactor: simplify user service
test: add unit tests for auth
\`\`\`

## Git Flow Workflow
1. **Start new feature**: \`git checkout -b feature/feature-name\`
2. **Work and commit**: Make changes, \`git add .\`, \`git commit -m "message"\`
3. **Push branch**: \`git push origin feature/feature-name\`
4. **Create Pull Request** on GitHub/GitLab
5. **Merge and cleanup**: Delete feature branch after merge

## Help Commands
\`\`\`bash
git help <command>            # Get help for specific command
git --help                    # General Git help
man git                       # Git manual page
\`\`\`

---
*This cheat sheet was generated by your Git setup script.*
*Keep it handy and update it as you learn more Git commands!*
EOF

    log_success "Created Git cheat sheet: $cheat_sheet_file"
    log_explain "This personalized reference includes commands specific to your $project_type project"
}

# Show post-setup tutorial
show_tutorial() {
    local project_type="$1"
    local branch_name="$2"
    
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${GREEN}🎉 Git Repository Setup Complete!${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    
    echo -e "${BLUE}📚 What Just Happened:${NC}"
    echo "1. ✅ Initialized Git repository (git init)"
    echo "2. ✅ Created .gitignore for $project_type project"
    echo "3. ✅ Made initial commit with your files"
    echo "4. ✅ Set up '$branch_name' as your main branch"
    [[ -n "$(git remote 2>/dev/null)" ]] && echo "5. ✅ Connected to remote repository"
    echo
    
    echo -e "${PURPLE}🚀 Next Steps - Your First Workflow:${NC}"
    echo
    echo "📝 Make Your Next Commit:"
    echo "   1. Edit some files in your project"
    echo "   2. Check what changed:     ${CYAN}git status${NC}"
    echo "   3. See the differences:    ${CYAN}git diff${NC}"
    echo "   4. Stage your changes:     ${CYAN}git add .${NC}"
    echo "   5. Commit your changes:    ${CYAN}git commit -m \"Your commit message\"${NC}"
    echo "   6. Push to remote:         ${CYAN}git push${NC}"
    echo
    echo "🔍 View Your History:"
    echo "   - Recent commits:          ${CYAN}git log --oneline -10${NC}"
    echo "   - Full history:            ${CYAN}git log${NC}"
    echo
    echo "🌿 Work with Branches:"
    echo "   - Create new branch:       ${CYAN}git checkout -b feature/your-feature${NC}"
    echo "   - List branches:           ${CYAN}git branch${NC}"
    echo "   - Switch branches:         ${CYAN}git checkout $branch_name${NC}"
    echo
    echo -e "${YELLOW}💡 Tip:${NC} Check the GIT_CHEATSHEET.md file for more commands tailored to your $project_type project!"
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Main function
main() {
    local directory
    directory=$(parse_args "$@")
    
    # Change to target directory
    cd "$directory" || {
        log_error "Failed to change to directory: $directory"
        exit 1
    }
    
    log_info "Initializing Git repository in $(pwd)"
    
    # Check system requirements
    local has_secret_tool
    check_requirements
    has_secret_tool=$?
    
    # Validate directory
    validate_directory "$(pwd)"
    
    # Configure Git credentials if possible
    configure_git_credentials "$has_secret_tool"
    
    # Initialize Git repository
    execute_with_explanation \
        "git init" \
        "Initializing new Git repository in the current directory"
    
    # Setup .gitignore
    setup_gitignore
    
    # Stage all files
    execute_with_explanation \
        "git add ." \
        "Staging all files in the directory for the initial commit"
    
    # Make initial commit
    execute_with_explanation \
        "git commit -m 'Initial commit'" \
        "Creating initial commit with all current files"
    
    # Prompt for branch name and rename if needed
    local branch_name
    branch_name=$(prompt_branch_name) || exit 1
    
    if [[ "$branch_name" != "master" ]]; then
        execute_with_explanation \
            "git branch -M \"$branch_name\"" \
            "Renaming default branch to $branch_name"
    fi
    
    # Setup remote repository
    setup_remote "$branch_name"
    
    # Generate cheat sheet if requested
    if [[ "$GENERATE_TUTORIAL" == "true" && -n "$PROJECT_TYPE" ]]; then
        generate_cheat_sheet "$PROJECT_TYPE" "$branch_name"
    fi
    
    # Show tutorial
    show_tutorial "$PROJECT_TYPE" "$branch_name"
    
    log_success "Git repository setup complete!"
}

# Run main function
main "$@"
