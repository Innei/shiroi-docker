#!/bin/bash

# Configuration synchronization script
# Ensures all required config files exist on remote server

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Configuration files to sync
CONFIG_FILES=(
    "docker-compose.yml"
    "nginx/nginx.conf"
    "nginx/upstream.conf"
    "nginx/upstream-blue.conf"
    "nginx/upstream-green.conf"
    "deploy-zero-downtime.sh"
    "first-time-deploy.sh"
    "shiroi.env.example"
    "compose.env.example"
)

# Function to check and create required directories
ensure_directories() {
    print_info "Ensuring required directories exist..."
    
    local dirs=(
        "$HOME/shiroi"
        "$HOME/shiroi/data"
        "$HOME/shiroi/logs" 
        "$HOME/shiroi/deploy"
        "$HOME/shiroi/deploy/nginx"
    )
    
    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            print_info "Creating directory: $dir"
            mkdir -p "$dir"
        fi
    done
}

# Function to sync config files
sync_configs() {
    print_info "Synchronizing configuration files..."
    
    local source_dir="."
    local target_dir="$HOME/shiroi/deploy"
    
    for file in "${CONFIG_FILES[@]}"; do
        local source_file="$source_dir/$file"
        local target_file="$target_dir/$file"
        local target_dir_path=$(dirname "$target_file")
        
        # Ensure target directory exists
        mkdir -p "$target_dir_path"
        
        if [ -f "$source_file" ]; then
            if [ -f "$target_file" ]; then
                # File exists, check if update needed
                if ! cmp -s "$source_file" "$target_file"; then
                    print_info "Updating: $file"
                    cp "$source_file" "$target_file"
                else
                    print_info "Up to date: $file"
                fi
            else
                # File doesn't exist, copy it
                print_info "Creating: $file"
                cp "$source_file" "$target_file"
            fi
        else
            print_warning "Source file not found: $source_file"
        fi
    done
}

# Function to ensure deployment scripts are executable
make_executable() {
    local scripts=(
        "$HOME/shiroi/deploy/deploy-zero-downtime.sh"
        "$HOME/shiroi/deploy/first-time-deploy.sh"
    )
    
    for script_file in "${scripts[@]}"; do
        if [ -f "$script_file" ]; then
            chmod +x "$script_file"
            print_success "Made $(basename "$script_file") executable"
        fi
    done
}

# Function to initialize default upstream config if needed
init_upstream_config() {
    local upstream_file="$HOME/shiroi/deploy/nginx/upstream.conf"
    local blue_config="$HOME/shiroi/deploy/nginx/upstream-blue.conf"
    
    if [ ! -f "$upstream_file" ] && [ -f "$blue_config" ]; then
        print_info "Initializing upstream config with blue configuration"
        cp "$blue_config" "$upstream_file"
    fi
}

# Function to check environment files
check_env_files() {
    print_info "Checking environment files..."
    
    # Check Shiroi app env file
    local shiroi_env="$HOME/shiroi/.env"
    local shiroi_example="$HOME/shiroi/deploy/shiroi.env.example"
    
    if [ ! -f "$shiroi_env" ]; then
        if [ -f "$shiroi_example" ]; then
            print_warning "Shiroi .env not found, creating from example"
            cp "$shiroi_example" "$shiroi_env"
            print_warning "Please edit $shiroi_env with your configuration"
        else
            print_error "Neither $shiroi_env nor $shiroi_example found"
        fi
    fi
    
    # Check compose env file
    local compose_env="$HOME/shiroi/deploy/.env"
    local compose_example="$HOME/shiroi/deploy/compose.env.example"
    
    if [ ! -f "$compose_env" ]; then
        if [ -f "$compose_example" ]; then
            print_info "Creating compose .env from example"
            cp "$compose_example" "$compose_env"
        else
            print_error "Compose env example not found: $compose_example"
        fi
    fi
}

# Main execution
main() {
    print_info "Starting configuration synchronization..."
    
    ensure_directories
    sync_configs
    make_executable
    init_upstream_config
    check_env_files
    
    print_success "Configuration synchronization completed!"
    
    # Show status
    print_info "Current configuration status:"
    echo "Deploy directory: $HOME/shiroi/deploy"
    ls -la "$HOME/shiroi/deploy/" 2>/dev/null || print_warning "Deploy directory empty"
    
    echo "Nginx configs:"
    ls -la "$HOME/shiroi/deploy/nginx/" 2>/dev/null || print_warning "Nginx config directory empty"
}

# Execute if run directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi