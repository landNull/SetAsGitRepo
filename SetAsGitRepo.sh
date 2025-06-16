#!/bin/bash

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly GENERAL_IGNORE=".env *.log .DS_Store .vscode .idea"

# Project-specific .gitignore templates
declare -A PROJECT_TEMPLATES=(
    ["node"]="node_modules/ npm-debug.log* yarn-debug.log* yarn-error.log* .npm .yarn-integrity .pnpm-debug.log* dist/ build/ coverage/"
    ["python"]="__pycache__/ *.py[cod] *\\$py.class *.so .Python build/ develop-eggs/ dist/ downloads/ eggs/ .eggs/ lib/ lib64/ parts/ sdist/ var/ wheels/ *.egg-info/ .installed.cfg *.egg .env .venv env/ venv/ ENV/ env.bak/ venv.bak/ .pytest_cache/ .coverage htmlcov/ .tox/ .cache .mypy_cache/ .dmypy.json dmypy.json"
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
readonly NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# Help function
show_help() {
    cat << EOF
Usage: $SCRIPT_NAME [DIRECTORY]

Initialize a Git repository with .gitignore setup and optional remote configuration.

Arguments:
    DIRECTORY    Target directory (default: current directory)

Options:
    -h, --help   Show this help message

Examples:
    $SCRIPT_NAME                    # Initialize in current directory
    $SCRIPT_NAME /path/to/project   # Initialize in specific directory
EOF
}

# Parse command line arguments
parse_args() {
    case "${1:-}" in
        -h|--help)
            show_help
            exit 0
            ;;
        -*)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
        *)
            echo "${1:-.}"
            ;;
    esac
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
        if git config --global credential.helper libsecret 2>/dev/null; then
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

# Validate .gitignore entry
is_valid_gitignore_entry() {
    local entry="$1"
    
    # Check if entry is non-empty
    if [[ -z "$entry" ]]; then
        return 1
    fi
    
    # Check for dangerous characters
    if [[ "$entry" =~ [<>|] ]]; then
        return 1
    fi
    
    # Check if entry contains a slash and doesn't end with one
    if [[ "$entry" == *"/"* && "$entry" != *"/" ]]; then
        return 1
    fi
    
    return 0
}

# Setup .gitignore
setup_gitignore() {
    echo
    log_info "Setting up .gitignore file..."
    
    if [[ ! -f ".gitignore" ]]; then
        touch .gitignore
        log_success "Created new .gitignore file"
    else
        log_info "Using existing .gitignore file"
    fi
    
    # Detect project types
    local -a detected_types
    mapfile -t detected_types < <(detect_project_type)
    
    local project_entries=""
    local recommended_type=""
    
    if [[ ${#detected_types[@]} -gt 0 ]]; then
        echo
        log_success "Detected project type(s): ${detected_types[*]}"
        recommended_type="${detected_types[0]}"  # Use first detected type as primary
        
        # Get entries for detected project type
        if project_entries=$(get_project_gitignore "$recommended_type"); then
            log_info "Recommended .gitignore entries for $recommended_type project:"
            echo "$project_entries" | tr ' ' '\n' | sed 's/^/  /'
        fi
    else
        echo
        log_info "No specific project type detected"
        show_project_types
        echo
        read -p "Enter project type for recommendations (or press Enter to skip): " recommended_type
        
        if [[ -n "$recommended_type" ]] && project_entries=$(get_project_gitignore "$recommended_type"); then
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
    read -p "Enter remote repository URL (or press Enter to skip): " remote_url
    
    if [[ -z "$remote_url" ]]; then
        log_info "No remote repository configured"
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
    git remote add origin "$remote_url"
    
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
    
    # Use credential helper approach instead of environment variables
    if git -c credential.helper='!f() { echo "username=$username"; echo "password=$token"; }; f' \
       push -u origin "$branch_name" 2>/dev/null; then
        log_success "Successfully pushed to remote repository"
    else
        log_error "Failed to push to remote repository"
        log_error "Please check your credentials and repository access"
        return 1
    fi
}

# Main function
main() {
    local target_dir
    target_dir=$(parse_args "$@")
    
    log_info "Initializing Git repository in: $target_dir"
    
    # Check requirements
    local has_secret_tool=1
    if ! check_requirements; then
        has_secret_tool=0
    fi
    
    # Validate and change to target directory
    validate_directory "$target_dir"
    cd "$target_dir" || exit 1
    
    # Configure Git credentials
    configure_git_credentials "$has_secret_tool"
    
    # Initialize repository
    log_info "Initializing Git repository..."
    git init
    
    # Setup .gitignore
    setup_gitignore
    
    # Stage files
    log_info "Staging files..."
    git add .
    
    # Check if we have files to commit
    if git diff --staged --quiet; then
        log_warning "No files to commit after applying .gitignore"
        log_info "Consider creating a README.md or other files"
        
        # Create a basic README if nothing to commit
        read -p "Create a basic README.md? (y/N): " create_readme
        if [[ "$create_readme" =~ ^[Yy]$ ]]; then
            echo "# $(basename "$PWD")" > README.md
            echo "## Description" >> README.md
            echo "Add your project description here." >> README.md
            git add README.md
        else
            log_error "No files to commit. Exiting."
            exit 1
        fi
    fi
    
    # Create initial commit
    log_info "Creating initial commit..."
    git commit -m "Initial commit"
    
    # Prompt for branch name and set it up
    local branch_name
    if ! branch_name=$(prompt_branch_name); then
        exit 1
    fi
    
    # Set the branch name if it's different from current
    local current_branch
    current_branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
    
    if [[ "$current_branch" != "$branch_name" ]]; then
        log_info "Setting branch name to: $branch_name"
        git branch -M "$branch_name"
    else
        log_info "Using current branch: $branch_name"
    fi
    
    # Setup remote (optional)
    setup_remote "$branch_name"
    
    log_success "Git repository successfully initialized in $target_dir!"
}

# Run main function with all arguments
main "$@"