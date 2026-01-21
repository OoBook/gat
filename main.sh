#!/bin/bash

# GAT - GitHub Actions Tester
# Universal workflow testing tool

set -e

# Version (replaced during installation)
GAT_VERSION="{{VERSION_TAG}}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default directories (can be overridden with flags)
CONFIG_DIR=".github/workflow-tests"
WORKFLOWS_DIR=".github/workflows"
GIT_PROJECT_DIR=""
ACT_FLAGS=""

# Function to parse flags
# This function is no longer used - kept for reference
# parse_flags() {
#     local remaining_args=()
#     
#     while [[ $# -gt 0 ]]; do
#         case $1 in
#             -c|--config-dir)
#                 CONFIG_DIR="$2"
#                 shift 2
#                 ;;
#             -w|--workflows-dir)
#                 WORKFLOWS_DIR="$2"
#                 shift 2
#                 ;;
#             -h|--help)
#                 show_help
#                 exit 0
#                 ;;
#             *)
#                 # Not a flag, save to remaining args
#                 remaining_args+=("$1")
#                 shift
#                 ;;
#         esac
#     done
#     
#     # Return remaining args as separate quoted arguments
#     printf '%q ' "${remaining_args[@]}"
# }

# Function to show help
show_help() {
    echo "Universal GitHub Actions Workflow Tester"
    echo ""
    echo "Usage: $0 [flags] <command> [options]"
    echo ""
    echo "Flags:"
    echo "  -c, --config-dir <path>       Set config directory (default: .github/workflow-tests)"
    echo "  -w, --workflows-dir <path>    Set workflows directory (default: .github/workflows)"
    echo "  -p, --project-dir <path>      Set git project directory (default: auto-detect)"
    echo "  -a, --act-flags <flags>       Additional flags to pass to act command"
    echo "  -h, --help                    Show this help message"
    echo ""
    echo "Commands:"
    echo "  list, ls                      List all workflows"
    echo "  init <workflow>               Initialize test scenarios for a workflow"
    echo "  list-scenarios <workflow>     List scenarios for a workflow"
    echo "  test <workflow> <num>         Test a specific scenario"
    echo "  test <workflow> <num> --act   Test with Act (requires Docker)"
    echo "  test-all <workflow>           Test all scenarios for a workflow"
    echo "  help                          Show this help message"
    echo ""
    echo "Arguments:"
    echo "  <workflow>  Workflow name (filename without extension) or number from list"
    echo "  <num>       Scenario number from list-scenarios"
    echo ""
    echo "Examples:"
    echo "  $0 list"
    echo "  $0 -w custom/workflows init 1"
    echo "  $0 -p path/to/repo -w .github/workflows list"
    echo "  $0 -a '--container-architecture linux/amd64' test workflow 1 --act"
    echo "  $0 -p my-repo -a '--verbose' test workflow 1 --act"
    echo "  $0 list-scenarios create-issue-branch"
    echo "  $0 test create-issue-branch 1"
    echo "  $0 test create-issue-branch 1 --act"
    echo "  $0 test-all create-issue-branch"
    echo ""
    echo "Dependencies:"
    echo "  Required: jq"
    echo "  Optional: yq, act, docker"
}

# Function to print colored output
print_step() { echo -e "${BLUE}===${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_info() { echo -e "${CYAN}ℹ${NC} $1"; }

# Function to get git root directory
get_git_root() {
    if [ -n "$GIT_PROJECT_DIR" ]; then
        # Use specified project directory
        if [ ! -d "$GIT_PROJECT_DIR" ]; then
            print_error "Specified project directory does not exist: $GIT_PROJECT_DIR"
            exit 1
        fi
        
        # Check if it's a git repository
        if ! git -C "$GIT_PROJECT_DIR" rev-parse --show-toplevel &>/dev/null; then
            print_error "Specified directory is not a git repository: $GIT_PROJECT_DIR"
            exit 1
        fi
        
        # Get the actual git root from that directory
        git -C "$GIT_PROJECT_DIR" rev-parse --show-toplevel
    else
        # Auto-detect git root
        git rev-parse --show-toplevel 2>/dev/null
    fi
}

# Function to check dependencies
check_dependencies() {
    local missing=()
    
    if ! command -v jq &> /dev/null; then
        missing+=("jq")
    fi
    
    if ! command -v yq &> /dev/null; then
        print_warning "yq not found (optional, for better YAML parsing)"
        print_info "Install with: brew install yq"
    fi
    
    if [ ${#missing[@]} -gt 0 ]; then
        print_error "Missing required dependencies: ${missing[*]}"
        print_info "Install with: brew install ${missing[*]}"
        exit 1
    fi
}

# Function to discover workflows
discover_workflows() {
    if [ ! -d "$WORKFLOWS_DIR" ]; then
        print_error "No workflows directory found: $WORKFLOWS_DIR"
        exit 1
    fi
    
    local workflows=()
    while IFS= read -r file; do
        workflows+=("$file")
    done < <(find "$WORKFLOWS_DIR" -type f \( -name "*.yml" -o -name "*.yaml" \) | sort)
    
    if [ ${#workflows[@]} -eq 0 ]; then
        print_error "No workflow files found in $WORKFLOWS_DIR"
        exit 1
    fi
    
    echo "${workflows[@]}"
}

# Function to extract workflow trigger from YAML
get_workflow_trigger() {
    local workflow_file=$1
    
    # Try with yq first (better YAML parsing)
    if command -v yq &> /dev/null; then
        yq eval '.on | keys | .[]' "$workflow_file" 2>/dev/null | head -n 1
    else
        # Fallback to grep
        grep -A 5 "^on:" "$workflow_file" | grep -E "^\s+[a-z_]+:" | head -n 1 | sed 's/://g' | xargs
    fi
}

# Function to get workflow name
get_workflow_name() {
    local workflow_file=$1
    
    if command -v yq &> /dev/null; then
        yq eval '.name' "$workflow_file" 2>/dev/null
    else
        grep "^name:" "$workflow_file" | sed 's/name://g' | xargs
    fi
}

# Function to list all workflows
list_workflows() {
    print_step "Available Workflows"
    echo ""
    
    local workflows=($(discover_workflows))
    local count=1
    
    for workflow in "${workflows[@]}"; do
        local name=$(get_workflow_name "$workflow")
        local trigger=$(get_workflow_trigger "$workflow")
        local basename=$(basename "$workflow")
        
        echo -e "${CYAN}$count.${NC} ${GREEN}$basename${NC}"
        echo -e "   Name: $name"
        echo -e "   Trigger: $trigger"
        echo -e "   Path: $workflow"
        echo ""
        ((count++))
    done
}

# Function to initialize test scenarios for a workflow
init_workflow_tests() {
    local workflow_file=$1
    
    if [ -z "$workflow_file" ]; then
        print_error "Please specify a workflow file"
        echo ""
        list_workflows
        exit 1
    fi
    
    # If number provided, get workflow by index
    if [[ "$workflow_file" =~ ^[0-9]+$ ]]; then
        local workflows=($(discover_workflows))
        workflow_file="${workflows[$((workflow_file - 1))]}"
    fi
    
    if [ ! -f "$workflow_file" ]; then
        print_error "Workflow file not found: $workflow_file"
        exit 1
    fi
    
    local workflow_name=$(get_workflow_name "$workflow_file")
    local trigger=$(get_workflow_trigger "$workflow_file")
    local basename=$(basename "$workflow_file" .yml)
    basename=$(basename "$basename" .yaml)
    
    print_step "Initializing tests for: $workflow_name"
    print_info "Trigger: $trigger"
    echo ""
    
    mkdir -p "$CONFIG_DIR"
    
    local scenarios_file="$CONFIG_DIR/${basename}-scenarios.json"
    
    # Generate scenario templates based on trigger type
    case "$trigger" in
        issues)
            cat > "$scenarios_file" << 'EOF'
{
  "workflow": "",
  "trigger": "issues",
  "scenarios": [
    {
      "name": "Feature from version branch",
      "description": "Test feature branch creation from 1.x",
      "event": {
        "action": "labeled",
        "issue": {
          "number": 101,
          "title": "[Enhancement]: Add user authentication",
          "labels": [
            {"name": "enhancement"},
            {"name": "planned"},
            {"name": "1.x"}
          ]
        }
      }
    },
    {
      "name": "Critical hotfix",
      "description": "Test critical bug creates hotfix from default branch",
      "event": {
        "action": "labeled",
        "issue": {
          "number": 102,
          "title": "[Bug]: Security vulnerability in auth",
          "labels": [
            {"name": "bug"},
            {"name": "planned"}
          ]
        },
        "severity": "Critical"
      }
    },
    {
      "name": "Regular bugfix",
      "description": "Test regular bugfix from dev branch",
      "event": {
        "action": "labeled",
        "issue": {
          "number": 103,
          "title": "[Bug]: Fix typo in documentation",
          "labels": [
            {"name": "bug"},
            {"name": "planned"}
          ]
        },
        "severity": "Low"
      }
    }
  ]
}
EOF
            ;;
        push)
            cat > "$scenarios_file" << 'EOF'
{
  "workflow": "",
  "trigger": "push",
  "scenarios": [
    {
      "name": "Push to main",
      "description": "Test push event to main branch",
      "event": {
        "ref": "refs/heads/main",
        "commits": [
          {
            "message": "Fix: resolve security issue",
            "author": {"name": "Test User"}
          }
        ]
      }
    }
  ]
}
EOF
            ;;
        pull_request)
            cat > "$scenarios_file" << 'EOF'
{
  "workflow": "",
  "trigger": "pull_request",
  "scenarios": [
    {
      "name": "PR opened",
      "description": "Test pull request opened event",
      "event": {
        "action": "opened",
        "pull_request": {
          "number": 1,
          "title": "Add new feature",
          "base": {"ref": "main"},
          "head": {"ref": "feature/test"}
        }
      }
    }
  ]
}
EOF
            ;;
        workflow_dispatch)
            cat > "$scenarios_file" << 'EOF'
{
  "workflow": "",
  "trigger": "workflow_dispatch",
  "scenarios": [
    {
      "name": "Manual trigger",
      "description": "Test manual workflow dispatch",
      "event": {
        "inputs": {
          "environment": "staging"
        }
      }
    }
  ]
}
EOF
            ;;
        *)
            cat > "$scenarios_file" << EOF
{
  "workflow": "",
  "trigger": "$trigger",
  "scenarios": [
    {
      "name": "Default scenario",
      "description": "Customize this scenario for your workflow",
      "event": {}
    }
  ]
}
EOF
            ;;
    esac
    
    # Update workflow path in scenarios file
    local workflow_rel_path=$(realpath --relative-to="$(pwd)" "$workflow_file" 2>/dev/null || echo "$workflow_file")
    if command -v jq &> /dev/null; then
        jq --arg wf "$workflow_rel_path" '.workflow = $wf' "$scenarios_file" > "$scenarios_file.tmp" && mv "$scenarios_file.tmp" "$scenarios_file"
    fi
    
    print_success "Created test scenarios: $scenarios_file"
    print_info "Edit this file to customize test scenarios"
    echo ""
    print_info "Next steps:"
    echo "  1. Edit $scenarios_file"
    echo "  2. Run: gat list-scenarios $basename"
    echo "  3. Run: gat test $basename 1"
}

# Function to list scenarios for a workflow
list_scenarios() {
    local workflow_name=$1
    
    if [ -z "$workflow_name" ]; then
        print_error "Please specify a workflow name"
        exit 1
    fi
    
    local scenarios_file="$CONFIG_DIR/${workflow_name}-scenarios.json"
    
    if [ ! -f "$scenarios_file" ]; then
        print_error "No scenarios found for workflow: $workflow_name"
        print_info "Run: gat init <workflow> first"
        exit 1
    fi
    
    local workflow_file=$(jq -r '.workflow' "$scenarios_file")
    local trigger=$(jq -r '.trigger' "$scenarios_file")
    
    print_step "Test Scenarios for: $workflow_name"
    print_info "Workflow: $workflow_file"
    print_info "Trigger: $trigger"
    echo ""
    
    local count=$(jq '.scenarios | length' "$scenarios_file")
    
    for i in $(seq 0 $((count - 1))); do
        local name=$(jq -r ".scenarios[$i].name" "$scenarios_file")
        local desc=$(jq -r ".scenarios[$i].description" "$scenarios_file")
        
        echo -e "${CYAN}$((i + 1)).${NC} ${GREEN}$name${NC}"
        echo "   $desc"
        echo ""
    done
}

# Function to generate event JSON
generate_event_json() {
    local scenarios_file=$1
    local scenario_index=$2
    
    local trigger=$(jq -r '.trigger' "$scenarios_file")
    local event=$(jq -r ".scenarios[$scenario_index].event" "$scenarios_file")
    
    # Get repository info
    local git_root
    git_root=$(get_git_root)
    
    local repo_name
    local repo_owner
    local default_branch
    
    if [ -n "$git_root" ]; then
        repo_name=$(basename "$git_root")
        repo_owner=$(git -C "$git_root" config --get remote.origin.url 2>/dev/null | sed -E 's/.*[:/]([^/]+)\/[^/]+\.git/\1/' || echo "test-owner")
        default_branch=$(git -C "$git_root" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")
    else
        repo_name="test-repo"
        repo_owner="test-owner"
        default_branch="main"
    fi
    
    # Build complete event JSON
    local event_file="$CONFIG_DIR/event.json"
    
    echo "$event" | jq --arg repo "$repo_name" \
                       --arg owner "$repo_owner" \
                       --arg branch "$default_branch" \
                       '. + {
                         repository: {
                           name: $repo,
                           owner: { login: $owner },
                           default_branch: $branch
                         }
                       }' > "$event_file"
    
    echo "$event_file"
}

# Function to run test with Act
run_with_act() {
    local workflow_file=$1
    local event_file=$2
    local trigger=$3
    
    if ! command -v act &> /dev/null; then
        print_warning "Act is not installed"
        print_info "Install with: brew install act"
        return 1
    fi
    
    if ! docker info &> /dev/null 2>&1; then
        print_warning "Docker is not running"
        return 1
    fi
    
    print_step "Running with Act (Docker)"
    print_info "Workflow: $workflow_file"
    print_info "Event: $event_file"
    echo ""
    
    # Find the git repository root
    local git_root
    git_root=$(get_git_root)
    
    if [ -z "$git_root" ]; then
        print_error "Not inside a git repository"
        print_info "Act requires running from within a git repository"
        print_info "Use -p/--project-dir to specify the git repository path"
        return 1
    fi
    
    # Convert paths to relative paths from git root (macOS compatible)
    local workflow_rel_path
    local event_rel_path
    
    # Get absolute paths first
    if [[ "$workflow_file" = /* ]]; then
        workflow_abs="$workflow_file"
    else
        workflow_abs="$(pwd)/$workflow_file"
    fi
    
    if [[ "$event_file" = /* ]]; then
        event_abs="$event_file"
    else
        event_abs="$(pwd)/$event_file"
    fi
    
    # Make paths relative to git root (portable way)
    # Remove the git_root prefix and any leading slash
    workflow_rel_path="${workflow_abs#$git_root/}"
    event_rel_path="${event_abs#$git_root/}"
    
    # If paths didn't change (not under git root), use as-is
    if [ "$workflow_rel_path" = "$workflow_abs" ]; then
        workflow_rel_path="$workflow_file"
    fi
    
    if [ "$event_rel_path" = "$event_abs" ]; then
        event_rel_path="$event_file"
    fi
    
    print_info "Git root: $git_root"
    print_info "Workflow (relative): $workflow_rel_path"
    print_info "Event (relative): $event_rel_path"
    echo ""
    
    # Change to git root and run act
    (
        cd "$git_root" || exit 1
        
        # Build act command with custom flags
        local act_cmd="act"
        
        # Add custom act flags if provided
        if [ -n "$ACT_FLAGS" ]; then
            act_cmd="$act_cmd $ACT_FLAGS"
        fi
        
        # Add trigger and workflow/event paths
        act_cmd="$act_cmd $trigger -W \"$workflow_rel_path\" -e \"$event_rel_path\""
        
        # Add secrets if file exists
        if [ -f ".secrets" ]; then
            act_cmd="$act_cmd --secret-file .secrets"
        fi
        
        print_info "Running from: $(pwd)"
        print_info "Command: $act_cmd"
        echo ""
        
        eval "$act_cmd"
    )
    
    local exit_code=$?
    
    if [ $exit_code -ne 0 ]; then
        echo ""
        print_warning "Act exited with code: $exit_code"
    fi
    
    return $exit_code
}

# Function to simulate workflow (dry run)
simulate_workflow() {
    local scenarios_file=$1
    local scenario_index=$2
    
    local name=$(jq -r ".scenarios[$scenario_index].name" "$scenarios_file")
    local event=$(jq -r ".scenarios[$scenario_index].event" "$scenarios_file")
    
    print_step "Simulating: $name"
    echo ""
    
    print_info "Event Data:"
    echo "$event" | jq '.'
    echo ""
    
    print_success "Event JSON generated successfully"
    print_info "This would trigger the workflow with the above event data"
}

# Function to test a specific scenario
test_scenario() {
    local workflow_name=$1
    local scenario_num=$2
    local use_act=${3:-false}
    
    if [ -z "$workflow_name" ] || [ -z "$scenario_num" ]; then
        print_error "Usage: test <workflow-name> <scenario-number> [--act]"
        exit 1
    fi
    
    local scenarios_file="$CONFIG_DIR/${workflow_name}-scenarios.json"
    
    if [ ! -f "$scenarios_file" ]; then
        print_error "No scenarios found for: $workflow_name"
        print_info "Run: gat init <workflow> first"
        exit 1
    fi
    

    local scenario_index=$((scenario_num - 1))
    # local workflow_file=$(jq -r '.workflow' "$scenarios_file")
    local workflow_file="$WORKFLOWS_DIR/$workflow_name.yml"

    local trigger=$(jq -r '.trigger' "$scenarios_file")
    
    # Generate event JSON
    local event_file=$(generate_event_json "$scenarios_file" "$scenario_index")
    
    if [ "$use_act" = true ]; then
        run_with_act "$workflow_file" "$event_file" "$trigger"
    else
        simulate_workflow "$scenarios_file" "$scenario_index"
    fi
}

# Main function
main() {
    # Parse flags directly in main
    local remaining_args=()
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--config-dir)
                CONFIG_DIR="$2"
                shift 2
                ;;
            -w|--workflows-dir)
                WORKFLOWS_DIR="$2"
                shift 2
                ;;
            -p|--project-dir)
                GIT_PROJECT_DIR="$2"
                CONFIG_DIR="$GIT_PROJECT_DIR/.github/workflow-tests"
                WORKFLOWS_DIR="$GIT_PROJECT_DIR/.github/workflows"
                shift 2
                ;;
            -a|--act-flags)
                ACT_FLAGS="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                echo "GAT version $GAT_VERSION"
                exit 0
                ;;
            *)
                # Not a flag, save to remaining args
                remaining_args+=("$1")
                shift
                ;;
        esac
    done
    
    # Set positional parameters to remaining args
    set -- "${remaining_args[@]}"
    
    local command=${1:-help}
    
    # Show directories being used if non-default
    if [ "$command" != "help" ] && [ "$command" != "" ]; then
        local show_info=false
        
        if [ "$CONFIG_DIR" != ".github/workflow-tests" ]; then
            print_info "Using config directory: $CONFIG_DIR"
            show_info=true
        fi
        
        if [ "$WORKFLOWS_DIR" != ".github/workflows" ]; then
            print_info "Using workflows directory: $WORKFLOWS_DIR"
            show_info=true
        fi
        
        if [ -n "$GIT_PROJECT_DIR" ]; then
            print_info "Using git project directory: $GIT_PROJECT_DIR"
            show_info=true
        fi

        if [ -n "$ACT_FLAGS" ]; then
            print_info "Act flags: $ACT_FLAGS"
            show_info=true
        fi
        
        if [ "$show_info" = true ]; then
            echo ""
        fi
    fi
    
    # Check dependencies
    if [ "$command" != "help" ] && [ "$command" != "" ]; then
        check_dependencies
    fi
    
    case "$command" in
        list|ls)
            list_workflows
            ;;
        init)
            init_workflow_tests "$2"
            ;;
        list-scenarios|scenarios)
            list_scenarios "$2"
            ;;
        test)
            local use_act=false
            if [ "$4" = "--act" ] || [ "$4" = "-a" ]; then
                use_act=true
            fi
            test_scenario "$2" "$3" "$use_act"
            ;;
        test-all)
            local workflow_name=$2
            local use_act=false
            if [ "$3" = "--act" ] || [ "$3" = "-a" ]; then
                use_act=true
            fi
            
            local scenarios_file="$CONFIG_DIR/${workflow_name}-scenarios.json"
            if [ ! -f "$scenarios_file" ]; then
                print_error "No scenarios found for: $workflow_name"
                exit 1
            fi
            
            local count=$(jq '.scenarios | length' "$scenarios_file")
            
            for i in $(seq 1 "$count"); do
                echo ""
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                test_scenario "$workflow_name" "$i" "$use_act"
            done
            ;;
        help|"")
            show_help
            ;;
        *)
            print_error "Unknown command: $command"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

main "$@"