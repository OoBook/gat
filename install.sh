#!/usr/bin/env bash

# GAT (GitHub Actions Tester) Installer
# Usage: 
#   curl -sSL https://raw.githubusercontent.com/oobook/gat/main/install.sh | bash
#   ./install.sh              # Install latest version
#   ./install.sh v1.0.0       # Install specific version

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
USER="oobook"
REPO="gat"
TOOL_NAME="gat"
SCRIPT_NAME="main.sh"
INSTALL_DIR="/usr/local/bin"

# Print functions
print_error() { echo -e "${RED}✗${NC} $1" >&2; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_info() { echo -e "${BLUE}ℹ${NC} $1"; }

# Check dependencies
check_dependencies() {
    local missing=()
    
    if ! command -v curl &> /dev/null; then
        missing+=("curl")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing+=("jq")
    fi
    
    if [ ${#missing[@]} -gt 0 ]; then
        print_error "Missing required dependencies: ${missing[*]}"
        echo ""
        echo "Install them with:"
        if [[ "$OSTYPE" == "darwin"* ]]; then
            echo "  brew install ${missing[*]}"
        elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
            echo "  sudo apt-get install ${missing[*]}"
        fi
        exit 1
    fi
}

# Get latest version from GitHub
get_latest_version() {
    local latest_version
    latest_version=$(curl -sSL "https://api.github.com/repos/$USER/$REPO/releases/latest" | jq -r .tag_name)
    
    if [ "$latest_version" == "null" ] || [ -z "$latest_version" ]; then
        print_error "Could not fetch latest release from GitHub"
        print_info "Falling back to main branch"
        echo "main"
    else
        echo "$latest_version"
    fi
}

# Check if version exists
version_exists() {
    local version=$1
    local url="https://api.github.com/repos/$USER/$REPO/releases/tags/$version"
    local response
    
    response=$(curl -sSL -w "%{http_code}" -o /dev/null "$url")
    
    if [ "$response" -eq 200 ]; then
        return 0
    else
        return 1
    fi
}

# Download script
download_script() {
    local version=$1
    local temp_file=$2
    local download_url
    
    # Construct the correct URL based on version
    if [ "$version" == "main" ]; then
        # Download from main branch
        download_url="https://raw.githubusercontent.com/$USER/$REPO/main/$SCRIPT_NAME"
    else
        # Download from tagged release (raw content from that tag)
        download_url="https://raw.githubusercontent.com/$USER/$REPO/$version/$SCRIPT_NAME"
    fi
    
    print_info "Downloading from: $download_url"
    
    local http_status
    http_status=$(curl -sSL -w "%{http_code}" "$download_url" -o "$temp_file" 2>&1 | tail -n1)
    
    if [ "$http_status" -ne 200 ]; then
        print_error "Failed to download (HTTP $http_status)"
        print_info "URL attempted: $download_url"
        return 1
    fi
    
    # Verify downloaded file is not empty
    if [ ! -s "$temp_file" ]; then
        print_error "Downloaded file is empty"
        return 1
    fi
    
    # Verify it's a shell script
    if ! head -n1 "$temp_file" | grep -q "^#!/"; then
        print_error "Downloaded file is not a valid shell script"
        return 1
    fi
    
    return 0
}

# Inject version into script
inject_version() {
    local temp_file=$1
    local version=$2
    
    print_info "Injecting version $version into script..."
    
    # Replace the version placeholder
    if grep -q "{{VERSION_TAG}}" "$temp_file"; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s/{{VERSION_TAG}}/$version/g" "$temp_file"
        else
            sed -i "s/{{VERSION_TAG}}/$version/g" "$temp_file"
        fi
        print_success "Version injected successfully"
    else
        print_warning "Version placeholder not found in script"
        print_info "The script may already have a version or use a different format"
    fi
}

# Check write permissions
check_permissions() {
    if [ ! -w "$INSTALL_DIR" ] && [ ! -d "$INSTALL_DIR" ]; then
        print_warning "Install directory $INSTALL_DIR requires sudo"
        return 1
    fi
    return 0
}

# Install script
install_script() {
    local temp_file=$1
    local use_sudo=$2
    
    chmod +x "$temp_file"
    
    if [ "$use_sudo" = true ]; then
        sudo mv "$temp_file" "$INSTALL_DIR/$TOOL_NAME"
    else
        mv "$temp_file" "$INSTALL_DIR/$TOOL_NAME"
    fi
}

# Verify installation
verify_installation() {
    # Check if command exists in PATH
    if ! command -v "$TOOL_NAME" &> /dev/null; then
        print_error "Command '$TOOL_NAME' not found in PATH"
        print_warning "You may need to add $INSTALL_DIR to your PATH or restart your terminal"
        echo ""
        echo "Try one of these:"
        echo "  1. Restart your terminal"
        echo "  2. Run: source ~/.zshrc  (or ~/.bashrc)"
        echo "  3. Add to PATH: export PATH=\"$INSTALL_DIR:\$PATH\""
        echo ""
        echo "Or run directly: $INSTALL_DIR/$TOOL_NAME --help"
        return 1
    fi
    
    # Get version
    local installed_version
    if installed_version=$("$TOOL_NAME" --version 2>/dev/null); then
        print_success "$TOOL_NAME installed successfully!"
        print_info "Version: $installed_version"
    else
        print_success "$TOOL_NAME installed successfully!"
        print_warning "Could not determine version (--version flag may not be implemented)"
    fi
    
    print_info "Location: $(which $TOOL_NAME)"
    return 0
}

# Main installation flow
main() {
    echo "╔═══════════════════════════════════════╗"
    echo "║  GAT - GitHub Actions Tester          ║"
    echo "║  Installation Script                  ║"
    echo "╚═══════════════════════════════════════╝"
    echo ""
    
    # Check dependencies
    print_info "Checking dependencies..."
    check_dependencies
    print_success "Dependencies OK"
    echo ""
    
    # Determine target version
    local target_version=$1
    
    if [ -z "$target_version" ]; then
        print_info "No version specified, fetching latest release..."
        target_version=$(get_latest_version)
        
        if [ "$target_version" == "main" ]; then
            print_warning "No releases found, using main branch"
        fi
    else
        # Clean up version format (remove 'refs/tags/' if present)
        target_version="${target_version#refs/tags/}"
        
        # Validate version format
        if [[ ! "$target_version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] && [ "$target_version" != "main" ]; then
            print_warning "Version format: expected 'v1.0.0' or 'main', got '$target_version'"
            print_info "Attempting to use anyway..."
        fi
        
        # Check if version exists (skip for 'main')
        if [ "$target_version" != "main" ]; then
            print_info "Verifying version $target_version exists..."
            if ! version_exists "$target_version"; then
                print_error "Version $target_version not found"
                print_info "Available releases: https://github.com/$USER/$REPO/releases"
                echo ""
                print_info "Fetching latest release instead..."
                target_version=$(get_latest_version)
                
                if [ "$target_version" == "main" ]; then
                    print_warning "No releases found, using main branch"
                fi
            fi
        fi
    fi
    
    print_success "Installing version: $target_version"
    echo ""
    
    # Download script
    print_info "Downloading $TOOL_NAME $target_version..."
    local temp_file="gat_tmp_$$"
    
    if ! download_script "$target_version" "$temp_file"; then
        rm -f "$temp_file"
        exit 1
    fi
    
    print_success "Download complete"
    echo ""
    
    # Inject version
    inject_version "$temp_file" "$target_version"
    
    # Check permissions
    local use_sudo=false
    if ! check_permissions; then
        use_sudo=true
    fi
    
    # Install
    print_info "Installing to $INSTALL_DIR/$TOOL_NAME..."
    
    if ! install_script "$temp_file" "$use_sudo"; then
        print_error "Installation failed"
        rm -f "$temp_file"
        exit 1
    fi
    
    echo ""
    
    # Verify
    verify_installation
    
    echo ""
    print_success "Installation complete!"
    echo ""
    echo "Get started with:"
    echo "  $TOOL_NAME --help"
    echo "  $TOOL_NAME list"
    echo ""
}

# Run main with all arguments
main "$@"