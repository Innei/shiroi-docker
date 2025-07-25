#!/bin/bash

# Shiroi Docker Rollback Script
# This script allows quick rollback between Docker image versions

set -e

# Configuration
IMAGE_NAME="shiroi"
CONTAINER_NAME="shiroi-app"
ENV_FILE="$HOME/shiroi/.env"
DATA_VOLUME="$HOME/shiroi/data:/app/data"
LOGS_VOLUME="$HOME/shiroi/logs:/app/logs"
PORT_MAPPING="-p 3000:13000 -p 2323:12323"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to list available image versions
list_versions() {
    print_info "Available Docker image versions:"
    docker images $IMAGE_NAME --format "table {{.Tag}}\t{{.CreatedAt}}\t{{.Size}}" | head -20
    
    echo
    print_info "Current running container:"
    if docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" | grep -q "$CONTAINER_NAME"; then
        docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" | grep "$CONTAINER_NAME"
    else
        print_warning "No container named '$CONTAINER_NAME' is currently running"
    fi
}

# Function to get current image tag
get_current_tag() {
    if docker ps --format "{{.Image}}" --filter "name=$CONTAINER_NAME" | grep -q "$IMAGE_NAME"; then
        docker ps --format "{{.Image}}" --filter "name=$CONTAINER_NAME" | head -1 | cut -d':' -f2
    else
        echo "none"
    fi
}

# Function to rollback to a specific version
rollback_to_version() {
    local target_tag=$1
    
    if [ -z "$target_tag" ]; then
        print_error "Please specify a target version tag"
        return 1
    fi
    
    # Check if the target image exists
    if ! docker images --format "{{.Tag}}" $IMAGE_NAME | grep -q "^${target_tag}$"; then
        print_error "Image $IMAGE_NAME:$target_tag not found"
        print_info "Available versions:"
        docker images $IMAGE_NAME --format "table {{.Tag}}\t{{.CreatedAt}}"
        return 1
    fi
    
    local current_tag=$(get_current_tag)
    if [ "$current_tag" = "$target_tag" ]; then
        print_warning "Already running version $target_tag"
        return 0
    fi
    
    print_info "Rolling back from $current_tag to $target_tag"
    
    # Stop and remove current container
    if docker ps -a --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        print_info "Stopping current container: $CONTAINER_NAME"
        docker stop $CONTAINER_NAME || true
        docker rm $CONTAINER_NAME || true
    fi
    
    # Start container with target version
    print_info "Starting container with version $target_tag"
    docker run -d \
        --name $CONTAINER_NAME \
        --restart unless-stopped \
        $PORT_MAPPING \
        --env-file $ENV_FILE \
        -v $DATA_VOLUME \
        -v $LOGS_VOLUME \
        $IMAGE_NAME:$target_tag
    
    # Wait and verify
    sleep 5
    if docker ps --format "{{.Names}}" | grep -q "$CONTAINER_NAME"; then
        print_success "Rollback completed successfully!"
        print_info "Container status:"
        docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" | grep "$CONTAINER_NAME"
        
        echo
        print_info "Recent logs:"
        docker logs --tail 10 $CONTAINER_NAME
    else
        print_error "Rollback failed! Container is not running"
        print_info "Container logs:"
        docker logs $CONTAINER_NAME
        return 1
    fi
}

# Function to rollback to previous version
rollback_to_previous() {
    local current_tag=$(get_current_tag)
    
    if [ "$current_tag" = "none" ]; then
        print_error "No container is currently running"
        return 1
    fi
    
    print_info "Current version: $current_tag"
    
    # Get available versions excluding current one
    local previous_tag=$(docker images $IMAGE_NAME --format "{{.Tag}}" | grep -v "latest" | grep -v "$current_tag" | head -1)
    
    if [ -z "$previous_tag" ]; then
        print_error "No previous version available for rollback"
        list_versions
        return 1
    fi
    
    print_info "Previous version found: $previous_tag"
    rollback_to_version $previous_tag
}

# Function to show help
show_help() {
    echo "Shiroi Docker Rollback Script"
    echo
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo
    echo "Commands:"
    echo "  list, ls              List available Docker image versions"
    echo "  rollback [TAG]        Rollback to a specific version tag"
    echo "  prev, previous        Rollback to the previous version"
    echo "  current              Show current running version"
    echo "  help, -h, --help     Show this help message"
    echo
    echo "Examples:"
    echo "  $0 list              # List all available versions"
    echo "  $0 rollback abc123   # Rollback to version with tag 'abc123'"
    echo "  $0 prev              # Rollback to previous version"
}

# Main script logic
case "${1:-help}" in
    "list" | "ls")
        list_versions
        ;;
    "rollback")
        rollback_to_version $2
        ;;
    "prev" | "previous")
        rollback_to_previous
        ;;
    "current")
        current_tag=$(get_current_tag)
        if [ "$current_tag" != "none" ]; then
            print_info "Current version: $current_tag"
        else
            print_warning "No container is currently running"
        fi
        ;;
    "help" | "-h" | "--help" | *)
        show_help
        ;;
esac