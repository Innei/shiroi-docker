#!/bin/bash

# Shiroi Load Balanced Deployment Script
# Deploys with both blue and green containers running simultaneously for load balancing

set -e

# Configuration
COMPOSE_FILE="docker-compose.yml"
PROJECT_NAME="shiroi"

# Container and service names
NGINX_CONTAINER="shiroi-nginx"
NGINX_SERVICE="shiroi-nginx"
BLUE_CONTAINER="shiroi-app-blue"
BLUE_SERVICE="shiroi-app-blue"
GREEN_CONTAINER="shiroi-app-green"
GREEN_SERVICE="shiroi-app-green"

# Configuration paths
NGINX_CONFIG_DIR="nginx"
UPSTREAM_CONF="nginx/upstream.conf"
BALANCED_CONF="nginx/upstream-balanced.conf"

# Health check settings
HEALTH_CHECK_TIMEOUT=60
HEALTH_CHECK_INTERVAL=5

# Application settings
APP_PORT="2323"
NGINX_HEALTH_URL="http://localhost:12333/nginx-health"

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
        if ! docker ps --filter "name=$container_name" --format "{{.Status}}" | grep -q "Up"; then
            print_error "Container $container_name is not running"
            return 1
        fi
        
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

# Function to enable load balancing
enable_load_balancing() {
    print_info "Enabling load balancing between blue and green containers..."
    
    local backup_file="${UPSTREAM_CONF}.backup.$(date +%s)"
    
    # Check if balanced config exists
    if [ ! -f "$BALANCED_CONF" ]; then
        print_error "Balanced config file $BALANCED_CONF not found"
        return 1
    fi
    
    # Backup current config
    cp $UPSTREAM_CONF $backup_file
    
    # Copy balanced config
    cp $BALANCED_CONF $UPSTREAM_CONF
    
    # Reload nginx
    print_info "Reloading nginx configuration..."
    if docker exec $NGINX_CONTAINER nginx -s reload 2>/dev/null; then
        print_success "Load balancing enabled successfully"
        rm -f $backup_file
        return 0
    else
        print_error "Failed to reload nginx configuration, restoring backup"
        mv $backup_file $UPSTREAM_CONF
        docker exec $NGINX_CONTAINER nginx -s reload 2>/dev/null || true
        return 1
    fi
}

# Function to deploy with load balancing
deploy_load_balanced() {
    local new_image=$1
    
    if [ -z "$new_image" ]; then
        print_error "Usage: $0 deploy <image_name:tag>"
        exit 1
    fi
    
    print_info "Starting load balanced deployment with image: $new_image"
    
    # Set image in environment
    export SHIROI_IMAGE=$new_image
    
    # Stop all services first
    print_info "Stopping existing services..."
    docker compose down || true
    
    # Start all services
    print_info "Starting all services..."
    docker compose up -d --remove-orphans
    
    # Check health of both containers
    print_info "Checking health of both containers..."
    
    if ! check_container_health $BLUE_CONTAINER $HEALTH_CHECK_TIMEOUT $HEALTH_CHECK_INTERVAL; then
        print_error "Blue container failed health check"
        exit 1
    fi
    
    if ! check_container_health $GREEN_CONTAINER $HEALTH_CHECK_TIMEOUT $HEALTH_CHECK_INTERVAL; then
        print_error "Green container failed health check"
        exit 1
    fi
    
    # Enable load balancing
    if ! enable_load_balancing; then
        print_error "Failed to enable load balancing"
        exit 1
    fi
    
    # Verify nginx is serving correctly
    sleep 5
    print_info "Verifying nginx is serving correctly..."
    if ! curl -f $NGINX_HEALTH_URL > /dev/null 2>&1; then
        print_error "Nginx health check failed"
        exit 1
    fi
    
    print_success "Load balanced deployment completed successfully!"
    print_info "Both blue and green containers are now serving traffic"
    
    # Show status
    docker ps --filter "name=shiroi"
}

# Function to show status
status() {
    print_info "Load balancing status:"
    print_info "Container status:"
    docker ps --filter "name=shiroi"
    
    print_info "Nginx upstream configuration:"
    grep -A 15 "upstream shiroi_backend" $UPSTREAM_CONF
    
    print_info "Testing load balancing..."
    for i in {1..5}; do
        echo "Request $i:"
        curl -s $NGINX_HEALTH_URL || echo "Failed"
    done
}

# Function to switch back to blue-green mode
switch_to_blue_green() {
    print_info "Switching back to blue-green deployment mode..."
    
    # Copy blue config to upstream
    cp "${NGINX_CONFIG_DIR}/upstream-blue.conf" $UPSTREAM_CONF
    
    # Reload nginx
    docker exec $NGINX_CONTAINER nginx -s reload
    
    # Stop green container
    docker compose stop $GREEN_SERVICE
    
    print_success "Switched back to blue-green mode (blue active)"
}

# Function to show help
show_help() {
    echo "Shiroi Load Balanced Deployment Script"
    echo
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo
    echo "Commands:"
    echo "  deploy <image>      Deploy with load balancing"
    echo "  status              Show load balancing status"
    echo "  enable-lb           Enable load balancing mode"
    echo "  switch-to-bg        Switch back to blue-green mode"
    echo "  stop                Stop all services"
    echo "  help                Show this help message"
    echo
    echo "Examples:"
    echo "  $0 deploy shiroi:latest"
    echo "  $0 status"
    echo "  $0 enable-lb"
    echo "  $0 switch-to-bg"
}

# Main script logic
case "${1:-help}" in
    "deploy")
        deploy_load_balanced $2
        ;;
    "status")
        status
        ;;
    "enable-lb")
        enable_load_balancing
        ;;
    "switch-to-bg")
        switch_to_blue_green
        ;;
    "stop")
        print_info "Stopping all services..."
        docker compose down
        ;;
    "help" | "-h" | "--help" | *)
        show_help
        ;;
esac 