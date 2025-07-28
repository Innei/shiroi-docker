#!/bin/bash

set -e

# First-time deployment script for Shiroi Docker deployment
# This script handles the initial deployment when no services are running

usage() {
    echo "Usage: $0 <image_name>"
    echo "Example: $0 shiroi:abc1234"
    exit 1
}

# Check if image parameter is provided
if [ $# -ne 1 ]; then
    usage
fi

NEW_IMAGE="$1"
# Container names based on docker-compose.yml
NGINX_CONTAINER="shiroi-nginx"
BLUE_CONTAINER="shiroi-app-blue" 
GREEN_CONTAINER="shiroi-app-green"

echo "========================================="
echo "Starting first-time deployment..."
echo "Image: $NEW_IMAGE"
echo "Target containers: $NGINX_CONTAINER, $BLUE_CONTAINER, $GREEN_CONTAINER"
echo "Current user: $(whoami)"
echo "========================================="

# Function to check if nginx container is running using docker ps
check_nginx_running() {
    if docker ps --filter "name=$NGINX_CONTAINER" --filter "status=running" --format "{{.Names}}" | grep -q "$NGINX_CONTAINER"; then
        return 0  # nginx is running
    else
        return 1  # nginx is not running
    fi
}

# Function to check if any shiroi containers are running
check_shiroi_containers_running() {
    if docker ps --filter "name=shiroi-app" --filter "status=running" --format "{{.Names}}" | grep -q shiroi-app; then
        return 0  # some shiroi containers are running
    else
        return 1  # no shiroi containers are running
    fi
}

# Function to check container health using docker ps
check_container_health() {
    local container_name="$1"
    local max_attempts=60  # 5 minutes with 5 second intervals
    local attempt=1
    
    echo "Checking health of container: $container_name"
    
    while [ $attempt -le $max_attempts ]; do
        # Check if container is running
        if ! docker ps --filter "name=$container_name" --filter "status=running" --format "{{.Names}}" | grep -q "$container_name"; then
            echo "Attempt $attempt/$max_attempts: Container $container_name is not running"
            sleep 5
            attempt=$((attempt + 1))
            continue
        fi
        
        # Check container health status if health check is configured
        health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "no-healthcheck")
        
        if [ "$health_status" = "healthy" ] || [ "$health_status" = "no-healthcheck" ]; then
            echo "Container $container_name is healthy"
            return 0
        elif [ "$health_status" = "unhealthy" ]; then
            echo "Attempt $attempt/$max_attempts: Container $container_name is unhealthy"
        else
            echo "Attempt $attempt/$max_attempts: Container $container_name health status: $health_status"
        fi
        
        sleep 5
        attempt=$((attempt + 1))
    done
    
    echo "Health check failed for container: $container_name"
    return 1
}

# Function to display container status using docker ps
show_container_status() {
    echo "Current container status:"
    echo "========================"
    docker ps --filter "name=shiroi" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo ""
}

# Function to check service availability
check_service_availability() {
    echo "Testing service availability..."
    local max_attempts=12  # 1 minute with 5 second intervals
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -f http://localhost:12333/nginx-health > /dev/null 2>&1; then
            echo "Service is available on port 12333"
            return 0
        else
            echo "Attempt $attempt/$max_attempts: Service not yet available on port 12333"
            sleep 5
            attempt=$((attempt + 1))
        fi
    done
    
    echo "Warning: Service health check on port 12333 failed after $max_attempts attempts"
    return 1
}

# Main deployment logic
main() {
    # Check if this is truly a first-time deployment
    if check_nginx_running; then
        echo "Error: Nginx container is already running. This is not a first-time deployment."
        echo "Use deploy-zero-downtime.sh for updates to existing deployments."
        show_container_status
        exit 1
    fi
    
    if check_shiroi_containers_running; then
        echo "Warning: Some Shiroi containers are running without nginx. Cleaning up..."
        # Stop any existing shiroi containers
        docker ps --filter "name=shiroi-app" --format "{{.Names}}" | xargs -r docker stop
        sleep 5
    fi
    
    echo "Confirmed: This is a first-time deployment"
    
    # Set the image environment variable for docker-compose
    export SHIROI_IMAGE="$NEW_IMAGE"
    echo "Using image: $SHIROI_IMAGE"
    
    # Start all services using docker-compose
    echo "Starting all services with docker-compose..."
    if ! docker compose up -d; then
        echo "Error: Failed to start services with docker-compose"
        exit 1
    fi
    
    echo "Services started. Waiting for containers to initialize..."
    sleep 10
    
    show_container_status
    
    # Check health of critical containers
    echo "Performing health checks..."
    
    # Get actual container names from docker ps
    nginx_container=$(docker ps --filter "name=$NGINX_CONTAINER" --format "{{.Names}}" | head -n1)
    blue_container=$(docker ps --filter "name=$BLUE_CONTAINER" --format "{{.Names}}" | head -n1)
    
    if [ -z "$nginx_container" ]; then
        echo "Error: Nginx container not found"
        docker compose logs nginx
        exit 1
    fi
    
    if [ -z "$blue_container" ]; then
        echo "Error: Shiroi blue container not found"
        docker compose logs shiroi-blue
        exit 1
    fi
    
    # Health check for nginx
    if ! check_container_health "$nginx_container"; then
        echo "Error: Nginx container health check failed"
        echo "Nginx logs:"
        docker logs "$nginx_container" --tail 50
        exit 1
    fi
    
    # Health check for blue container
    if ! check_container_health "$blue_container"; then
        echo "Error: Shiroi blue container health check failed"
        echo "Blue container logs:"
        docker logs "$blue_container" --tail 50
        exit 1
    fi
    
    # Final service availability check
    echo "Waiting additional 20 seconds for services to fully initialize..."
    sleep 20
    
    if ! check_service_availability; then
        echo "Error: Service availability check failed"
        echo "Container status:"
        show_container_status
        echo "Nginx logs:"
        docker logs "$nginx_container" --tail 20
        echo "Blue container logs:"
        docker logs "$blue_container" --tail 20
        exit 1
    fi
    
    echo "========================================="
    echo "First-time deployment completed successfully!"
    echo "Service is available at: http://localhost:12333"
    echo "Health check endpoint: http://localhost:12333/nginx-health"
    echo "========================================="
    
    show_container_status
}

# Run main function
main 