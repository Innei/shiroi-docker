#!/bin/bash

# Shiroi Zero-Downtime Deployment Script
# Uses Docker Compose blue-green deployment strategy

set -e

# Configuration
# Docker Compose settings
COMPOSE_FILE="docker-compose.yml"
PROJECT_NAME="shiroi"

# Container and service names
NGINX_CONTAINER="shiroi-nginx"          # Nginx container name
NGINX_SERVICE="shiroi-nginx"            # Nginx service name in compose
BLUE_CONTAINER="shiroi-app-blue"        # Blue app container name
BLUE_SERVICE="shiroi-app-blue"          # Blue app service name in compose
GREEN_CONTAINER="shiroi-app-green"      # Green app container name
GREEN_SERVICE="shiroi-app-green"        # Green app service name in compose

# Configuration paths and directories
NGINX_CONFIG_DIR="nginx"                # Nginx config directory
UPSTREAM_CONF="nginx/upstream.conf"     # Active upstream config file

# Health check settings
HEALTH_CHECK_TIMEOUT=60                 # Timeout for health checks (seconds)
HEALTH_CHECK_INTERVAL=5                 # Interval between health checks (seconds)

# Service settings
GREEN_PROFILE="green"                   # Docker compose profile for green deployment
APP_PORT="2323"                         # Application port
NGINX_HEALTH_URL="http://localhost:12333/nginx-health"  # Nginx health check URL

# Docker command settings
CONTAINER_NAME_FILTER="name=shiroi"     # Filter for container queries
NGINX_RELOAD_CMD="nginx -s reload"      # Nginx reload command

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

# Function to check if container is healthy
check_container_health() {
    local container_name=$1
    local timeout=$2
    local interval=$3
    
    print_info "Checking health of $container_name..."
    
    for ((i=0; i<timeout; i+=interval)); do
        # Check if container exists and is running
        if ! docker ps --filter "name=$container_name" --format "{{.Status}}" | grep -q "Up"; then
            print_error "Container $container_name is not running"
            return 1
        fi
        
        # Check container health status
        local health_status=$(docker inspect $container_name --format='{{.State.Health.Status}}' 2>/dev/null || echo "unknown")
        
        if [ "$health_status" = "healthy" ]; then
            print_success "$container_name is healthy"
            return 0
        fi
        
        if [ "$health_status" = "unhealthy" ]; then
            print_error "$container_name is unhealthy"
            return 1
        fi
        
        print_info "Waiting for $container_name to become healthy... (${i}s/${timeout}s)"
        sleep $interval
    done
    
    print_error "Health check timeout for $container_name"
    return 1
}

# Function to get current active color
get_current_color() {
    local blue_running=$(docker ps --filter "name=$BLUE_CONTAINER" --format "{{.Status}}" | grep -c "Up" || echo "0")
    local green_running=$(docker ps --filter "name=$GREEN_CONTAINER" --format "{{.Status}}" | grep -c "Up" || echo "0")
    
    if [ "$blue_running" = "1" ]; then
        if [ "$green_running" = "1" ]; then
            # Both running, check nginx upstream config
            if grep -q "${GREEN_SERVICE}:${APP_PORT}" $UPSTREAM_CONF && ! grep -q "# server ${GREEN_SERVICE}:${APP_PORT}" $UPSTREAM_CONF; then
                echo "green"
            else
                echo "blue"
            fi
        else
            echo "blue"
        fi
    elif [ "$green_running" = "1" ]; then
        echo "green"
    else
        echo "none"
    fi
}

# Function to switch nginx upstream
switch_upstream() {
    local target_color=$1
    local backup_file="${UPSTREAM_CONF}.backup.$(date +%s)"
    local source_file="${NGINX_CONFIG_DIR}/upstream-${target_color}.conf"
    
    print_info "Switching nginx upstream to $target_color..."
    
    # Check if source file exists
    if [ ! -f "$source_file" ]; then
        print_error "Source config file $source_file not found"
        return 1
    fi
    
    # Backup current config
    cp $UPSTREAM_CONF $backup_file
    
    # Copy the appropriate upstream config
    cp $source_file $UPSTREAM_CONF
    
    # Reload nginx configuration
    print_info "Reloading nginx configuration..."
    
    # Debug: Show docker compose services
    print_info "Available docker compose services:"
    docker compose ps --services 2>/dev/null || docker-compose ps --services 2>/dev/null || true
    
    # Check if nginx container is running first
    if ! docker ps --filter "name=$NGINX_CONTAINER" --format "{{.Names}}" | grep -q "^${NGINX_CONTAINER}$"; then
        print_error "Nginx container $NGINX_CONTAINER is not running"
        print_info "Starting nginx service..."
        if ! docker compose up -d $NGINX_SERVICE 2>/dev/null; then
            print_warning "docker compose failed, trying docker-compose..."
            docker-compose up -d $NGINX_SERVICE 2>/dev/null || true
        fi
        sleep 5
    fi
    
    # Try to reload nginx with error handling
    print_info "Attempting to reload nginx configuration..."
    local reload_success=false
    
    # Try modern docker compose syntax first
    if docker compose exec $NGINX_SERVICE $NGINX_RELOAD_CMD 2>/dev/null; then
        reload_success=true
    # Fallback to legacy docker-compose syntax
    elif docker-compose exec $NGINX_SERVICE $NGINX_RELOAD_CMD 2>/dev/null; then
        reload_success=true
    # Fallback to direct docker exec
    elif docker exec $NGINX_CONTAINER $NGINX_RELOAD_CMD 2>/dev/null; then
        reload_success=true
    fi
    
    if [ "$reload_success" = true ]; then
        print_success "Nginx configuration reloaded successfully"
        rm -f $backup_file
        return 0
    else
        print_error "Failed to reload nginx configuration with all methods, restoring backup"
        mv $backup_file $UPSTREAM_CONF
        # Try to reload again with the backup config (silent)
        docker compose exec $NGINX_SERVICE $NGINX_RELOAD_CMD 2>/dev/null || \
        docker-compose exec $NGINX_SERVICE $NGINX_RELOAD_CMD 2>/dev/null || \
        docker exec $NGINX_CONTAINER $NGINX_RELOAD_CMD 2>/dev/null || true
        return 1
    fi
}

# Function to clean up containers
cleanup_container() {
    local container_name=$1
    
    print_info "Cleaning up container: $container_name"
    
    # Check if container exists (running or stopped)
    if docker ps -a --filter "name=$container_name" --format "{{.Names}}" | grep -q "^${container_name}$"; then
        print_info "Found existing container $container_name, removing it..."
        
        # Stop container if it's running
        if docker ps --filter "name=$container_name" --format "{{.Names}}" | grep -q "^${container_name}$"; then
            docker stop $container_name
        fi
        
        # Remove container
        docker rm $container_name
        print_success "Container $container_name removed successfully"
    else
        print_info "No existing container $container_name found"
    fi
}

# Function to perform zero-downtime deployment
deploy() {
    local new_image=$1
    
    if [ -z "$new_image" ]; then
        print_error "Usage: $0 deploy <image_name:tag>"
        exit 1
    fi
    
    # Check if the image exists locally
    local image_name=$(echo $new_image | cut -d':' -f1)
    local image_tag=$(echo $new_image | cut -d':' -f2)
    
    if ! docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^${new_image}$"; then
        print_error "Image $new_image not found locally"
        print_info "Available images:"
        print_info "Git Hash Tags:"
        docker images $image_name --format "table {{.Tag}}\t{{.CreatedAt}}" | grep -E "(TAG|^[a-f0-9]{7}$)"
        print_info "Date Tags:"
        docker images $image_name --format "table {{.Tag}}\t{{.CreatedAt}}" | grep -E "(TAG|^[0-9]{8}_[0-9]{4}$)"
        print_info "Other Tags:"
        docker images $image_name --format "table {{.Tag}}\t{{.CreatedAt}}" | grep -vE "(^[a-f0-9]{7}$|^[0-9]{8}_[0-9]{4}$)"
        exit 1
    fi
    
    print_info "Starting zero-downtime deployment with image: $new_image"
    
    # Clean up any orphan containers first
    print_info "Checking for orphan containers..."
    docker compose down --remove-orphans > /dev/null 2>&1 || true
    
    # Ensure nginx service is running
    print_info "Ensuring nginx service is running..."
    if ! docker compose up -d $NGINX_SERVICE 2>/dev/null; then
        print_warning "docker compose failed, trying docker-compose..."
        docker-compose up -d $NGINX_SERVICE 2>/dev/null || true
    fi
    
    # Get current active color
    local current_color=$(get_current_color)
    print_info "Current active color: $current_color"
    
    # Determine target color
    local target_color
    if [ "$current_color" = "blue" ]; then
        target_color="green"
    else
        target_color="blue"
    fi
    
    print_info "Deploying to: $target_color"
    
    # Clean up target container if it exists
    local target_container
    if [ "$target_color" = "green" ]; then
        target_container=$GREEN_CONTAINER
    else
        target_container=$BLUE_CONTAINER
    fi
    
    cleanup_container $target_container
    
    # Set image in environment
    export SHIROI_IMAGE=$new_image
    
    # Start target container
    print_info "Starting $target_color container..."
    if [ "$target_color" = "green" ]; then
        if ! docker compose --profile $GREEN_PROFILE up -d --remove-orphans $GREEN_SERVICE 2>/dev/null; then
            print_warning "docker compose failed, trying docker-compose..."
            docker-compose --profile $GREEN_PROFILE up -d --remove-orphans $GREEN_SERVICE 2>/dev/null || true
        fi
    else
        if ! docker compose up -d --remove-orphans $BLUE_SERVICE 2>/dev/null; then
            print_warning "docker compose failed, trying docker-compose..."
            docker-compose up -d --remove-orphans $BLUE_SERVICE 2>/dev/null || true
        fi
    fi
    
    # Wait for container to be healthy
    if [ "$target_color" = "green" ]; then
        target_container=$GREEN_CONTAINER
    else
        target_container=$BLUE_CONTAINER
    fi
    
    if ! check_container_health $target_container $HEALTH_CHECK_TIMEOUT $HEALTH_CHECK_INTERVAL; then
        print_error "New container failed health check, rolling back..."
        docker compose stop $target_container
        exit 1
    fi
    
    # Switch nginx upstream
    if ! switch_upstream $target_color; then
        print_error "Failed to switch nginx upstream, rolling back..."
        docker compose stop $target_container
        exit 1
    fi
    
    # Wait a bit to ensure traffic is flowing
    sleep 10
    
    # Verify nginx is serving correctly
    print_info "Verifying nginx is serving correctly..."
    if ! curl -f $NGINX_HEALTH_URL > /dev/null 2>&1; then
        print_error "Nginx health check failed, rolling back..."
        switch_upstream $current_color
        docker compose stop $target_container
        exit 1
    fi
    
    # Stop old container
    local old_container
    if [ "$current_color" = "blue" ]; then
        old_container=$BLUE_CONTAINER
    elif [ "$current_color" = "green" ]; then
        old_container=$GREEN_CONTAINER
    fi
    
    if [ "$old_container" != "" ]; then
        print_info "Stopping old container: $old_container"
        docker compose stop $old_container
    fi
    
    print_success "Zero-downtime deployment completed successfully!"
    print_info "Active color is now: $target_color"
    
    # Show status
    docker ps --filter "$CONTAINER_NAME_FILTER-"
}

# Function to rollback
rollback() {
    local current_color=$(get_current_color)
    
    if [ "$current_color" = "none" ]; then
        print_error "No containers are currently running"
        exit 1
    fi
    
    local target_color
    if [ "$current_color" = "blue" ]; then
        target_color="green"
    else
        target_color="blue"
    fi
    
    print_info "Rolling back from $current_color to $target_color"
    
    # Clean up target container if it exists
    local target_container
    if [ "$target_color" = "green" ]; then
        target_container=$GREEN_CONTAINER
    else
        target_container=$BLUE_CONTAINER
    fi
    
    cleanup_container $target_container
    
    # Start target container
    if [ "$target_color" = "green" ]; then
        if ! docker compose --profile $GREEN_PROFILE up -d --remove-orphans $GREEN_SERVICE 2>/dev/null; then
            print_warning "docker compose failed, trying docker-compose..."
            docker-compose --profile $GREEN_PROFILE up -d --remove-orphans $GREEN_SERVICE 2>/dev/null || true
        fi
    else
        if ! docker compose up -d --remove-orphans $BLUE_SERVICE 2>/dev/null; then
            print_warning "docker compose failed, trying docker-compose..."
            docker-compose up -d --remove-orphans $BLUE_SERVICE 2>/dev/null || true
        fi
    fi
    
    # Check health and switch
    if check_container_health $target_container $HEALTH_CHECK_TIMEOUT $HEALTH_CHECK_INTERVAL; then
        switch_upstream $target_color
        print_success "Rollback completed successfully!"
    else
        print_error "Rollback failed - target container is not healthy"
        docker compose stop $target_container
        exit 1
    fi
}

# Function to show status
status() {
    local current_color=$(get_current_color)
    print_info "Current active color: $current_color"
    print_info "Container status:"
    docker ps --filter "$CONTAINER_NAME_FILTER-"
    
    print_info "Nginx upstream configuration:"
    grep -A 10 "upstream shiroi_backend" $UPSTREAM_CONF
}

# Function to clean up all containers and orphans
cleanup_all() {
    print_info "Cleaning up all shiroi containers and orphans..."
    
    # Stop and remove all project containers with orphan cleanup
    docker compose down --remove-orphans
    
    # Remove any remaining shiroi containers manually
    for container in $BLUE_CONTAINER $GREEN_CONTAINER $NGINX_CONTAINER; do
        if docker ps -a --filter "name=$container" --format "{{.Names}}" | grep -q "^${container}$"; then
            print_info "Removing orphan container: $container"
            docker stop $container 2>/dev/null || true
            docker rm $container 2>/dev/null || true
        fi
    done
    
    print_success "Cleanup completed"
}

# Function to debug deployment environment
debug() {
    print_info "=== Shiroi Deployment Debug Information ==="
    
    print_info "Docker version:"
    docker --version
    
    print_info "Docker Compose version:"
    docker compose version 2>/dev/null || docker-compose version 2>/dev/null || echo "Docker Compose not found"
    
    print_info "Current directory:"
    pwd
    
    print_info "Files in current directory:"
    ls -la
    
    print_info "Docker Compose file check:"
    if [ -f "docker-compose.yml" ]; then
        print_success "docker-compose.yml found"
        print_info "Services defined in docker-compose.yml:"
        grep "^  [a-zA-Z]" docker-compose.yml | sed 's/:$//' || true
    else
        print_error "docker-compose.yml not found"
    fi
    
    print_info "Nginx config files:"
    ls -la $NGINX_CONFIG_DIR/ 2>/dev/null || print_warning "nginx directory not found"
    
    print_info "Running containers:"
    docker ps --filter "$CONTAINER_NAME_FILTER" || true
    
    print_info "All shiroi-related containers (including stopped):"
    docker ps -a --filter "$CONTAINER_NAME_FILTER" || true
    
    print_info "Docker Compose services status:"
    docker compose ps 2>/dev/null || docker-compose ps 2>/dev/null || print_warning "Could not get compose services"
    
    print_info "Environment variables:"
    echo "SHIROI_IMAGE=${SHIROI_IMAGE:-not set}"
    echo "HOME=${HOME:-not set}"
}

# Function to show help
show_help() {
    echo "Shiroi Zero-Downtime Deployment Script"
    echo
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo
    echo "Commands:"
    echo "  deploy <image>   Deploy new image with zero downtime"
    echo "  rollback         Rollback to previous deployment"
    echo "  status           Show current deployment status"
    echo "  stop             Stop all services"
    echo "  start            Start all services"
    echo "  cleanup          Clean up all containers and orphans"
    echo "  debug            Show debug information"
    echo "  help             Show this help message"
    echo
    echo "Examples:"
    echo "  $0 deploy shiroi:abc123"
    echo "  $0 rollback"
    echo "  $0 status"
    echo "  $0 cleanup"
    echo "  $0 debug"
}

# Main script logic
case "${1:-help}" in
    "deploy")
        deploy $2
        ;;
    "rollback")
        rollback
        ;;
    "status")
        status
        ;;
    "stop")
        print_info "Stopping all services..."
        docker compose down
        ;;
    "start")
        print_info "Starting services..."
        docker compose up -d --remove-orphans
        ;;
    "cleanup")
        cleanup_all
        ;;
    "debug")
        debug
        ;;
    "help" | "-h" | "--help" | *)
        show_help
        ;;
esac