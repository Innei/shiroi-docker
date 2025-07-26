# Shiroi Docker Zero-Downtime Deployment System - AI Memory

## Project Overview

This project implements a zero-downtime blue-green deployment solution for Shiroi (closed-source version of Shiro) using Docker Compose and Nginx reverse proxy. The system enables automatic build and deployment through GitHub Actions with true zero-downtime upgrades.

## Core Architecture

```
External Access :12323 → Nginx → Blue-Green NextJS Containers
                               ├─ shiroi-blue:3001  
                               └─ shiroi-green:3002
```

**Key Design Principles:**
- External port remains constant (only 12323:2323)
- Zero-downtime achieved through internal blue-green container switching
- Nginx serves as reverse proxy and traffic switcher

## Main Implementation Components

### 1. Docker Compose Configuration (`docker-compose.yml`)

**Service Structure:**
- `nginx`: Nginx reverse proxy, listening on 12323:2323
- `shiroi-blue`: Blue application container, internal port 3001
- `shiroi-green`: Green application container, internal port 3002, uses profile by default

**Key Features:**
- Health checks use NextJS root path `/`
- Resource limits: 500MB memory
- Data persistence mapped to `$HOME/shiroi/data` and `$HOME/shiroi/logs`
- Environment variable `${SHIROI_IMAGE}` controls image version

### 2. Nginx Configuration System

**Core Files:**
- `nginx/nginx.conf`: Main config, defines 2323 port server
- `nginx/upstream.conf`: Current active upstream configuration
- `nginx/upstream-blue.conf`: Blue deployment configuration template
- `nginx/upstream-green.conf`: Green deployment configuration template

**Design Highlights:**
- Separated configuration files, avoiding hardcoded configs
- Configuration switching via file copying
- Supports health check endpoint `/nginx-health`

### 3. Zero-Downtime Deployment Script (`deploy-zero-downtime.sh`)

**Core Functions:**
- `deploy <image>`: Execute zero-downtime deployment
- `rollback`: Rollback to previous version
- `status`: View current status
- `start/stop`: Service management

**Blue-Green Switch Logic:**
1. Detect current active color
2. Start target color container
3. Health check new container
4. Switch Nginx configuration (`switch_upstream` function)
5. Verify traffic switch success
6. Stop old container

**Key Functions:**
- `get_current_color()`: Detect current active color
- `switch_upstream()`: Switch Nginx config via file copying
- `check_container_health()`: Container health checking

### 4. Configuration Sync System (`sync-configs.sh`)

**Core Responsibilities:**
- Ensure remote server directory structure integrity
- Sync all configuration files to server
- Intelligent updates: compare file differences, only update changed files
- Initialize environment variable files

**Managed File List:**
```bash
CONFIG_FILES=(
    "docker-compose.yml"
    "nginx/nginx.conf" 
    "nginx/upstream.conf"
    "nginx/upstream-blue.conf"
    "nginx/upstream-green.conf"
    "deploy-zero-downtime.sh"
    "shiroi.env.example"
    "compose.env.example"
)
```

### 5. GitHub Actions Workflow (`.github/workflows/deploy.yml`)

**Enhanced Features:**
- Build multi-tag images: `latest`, `{git-hash}`, `{date_time}`
- Retain specified number of historical versions for rollback
- Automatically upload and sync configuration files
- Auto-detect first deployment vs zero-downtime upgrade

**Deployment Flow:**
1. **Prepare Phase**: Read build hash, determine if rebuild needed
2. **Build Phase**: Docker build, generate multi-tag images
3. **Deploy Phase**: 
   - Upload images and configuration files
   - Run configuration sync script
   - Execute zero-downtime deployment or first deployment
   - Clean old image versions
4. **Verification Phase**: Health checks, update hash records

## Environment Variable File System

**File Separation Design:**
- `shiroi.env.example` → `$HOME/shiroi/.env` (Shiroi application config)
- `compose.env.example` → `$HOME/shiroi/deploy/.env` (Docker Compose config)

**Purpose Distinction:**
- Shiroi application config: API URLs, tokens, runtime environment
- Compose config: Image versions, deployment parameters

## Rollback System Optimization (`rollback.sh`)

**Enhanced Features:**
- Support multiple tag format recognition: git hash (7 chars), date tags, others
- Intelligent version finding: prioritize git hash, then date tags
- Categorized image version display for easy selection

## Key Technical Decisions

### 1. Port Design
**Remove port 13000, keep only 12323:**
- Simplify configuration, reduce maintenance cost
- Unified external service port
- Internal blue-green switching still uses 3001/3002 ports

### 2. Health Check Strategy
**Use NextJS root path `/`:**
- Closer to real user access patterns
- Judge service health by HTTP status codes (200 vs 5xx)
- No need for special health check endpoints

### 3. Configuration Management Strategy
**Separate static configuration files:**
- Avoid hardcoded configs in scripts
- Easy maintenance and version control
- Support independent configuration updates

### 4. Image Version Management
**Multi-tag Strategy:**
- `latest`: Latest version
- `{git-hash}`: Stable identifier based on code commits
- `{date_time}`: Time-based version identifier
- Retain multiple historical versions for quick rollback

## Deployment Directory Structure

```
$HOME/shiroi/
├── .env                    # Shiroi application environment variables
├── data/                   # Application data persistence
├── logs/                   # Application logs
└── deploy/                 # Deployment files directory
    ├── .env                # Docker Compose environment variables
    ├── docker-compose.yml  # Main orchestration file
    ├── deploy-zero-downtime.sh  # Deployment script
    ├── sync-configs.sh     # Configuration sync script
    ├── shiroi.env.example  # Application config example
    ├── compose.env.example # Orchestration config example
    └── nginx/              # Nginx configuration directory
        ├── nginx.conf      # Main configuration
        ├── upstream.conf   # Current upstream configuration
        ├── upstream-blue.conf   # Blue configuration template
        └── upstream-green.conf  # Green configuration template
```

## Usage Summary

### First Deployment
1. Fork project, configure GitHub Secrets
2. Push code to trigger automatic build and deployment
3. System auto-detects first deployment, starts all services

### Daily Upgrades
1. Push code to main branch
2. GitHub Actions automatically builds new image
3. Execute zero-downtime blue-green deployment
4. Verify deployment success, clean old versions

### Manual Operations
```bash
cd $HOME/shiroi/deploy

# Zero-downtime deployment
./deploy-zero-downtime.sh deploy shiroi:new-tag

# View status
./deploy-zero-downtime.sh status

# Rollback
./deploy-zero-downtime.sh rollback

# Traditional rollback
./rollback.sh prev
```

## Failure Recovery Mechanisms

**Auto-rollback Trigger Conditions:**
- New container health check failure
- Nginx configuration reload failure
- Service availability verification failure

**Rollback Strategy:**
- Retain configuration backup files
- Quick recovery to last stable version
- Multi-layer verification ensures service availability

## Monitoring and Verification

**Health Check Hierarchy:**
1. Docker container health checks (application layer)
2. Nginx configuration verification (proxy layer)
3. End-to-end service availability testing (user layer)

**Verification Endpoints:**
- `http://localhost:12323/` - Application homepage
- `http://localhost:12323/nginx-health` - Nginx health status

## Performance Optimization

**Resource Management:**
- Container memory limit: 500MB
- Retained historical versions: 3 (configurable)
- Cache strategy: Docker BuildKit cache

**Network Optimization:**
- Nginx keepalive connection reuse
- Reasonable timeout configurations
- Failure retry mechanisms

## Security Considerations

**Access Control:**
- SSH key authentication
- Environment variable isolation
- Configuration file permission control

**Data Protection:**
- Configuration backup mechanisms
- Data volume persistence
- Rollback point protection

## Extension Capabilities

**Extensible Design:**
- Support for more color containers (red, green, blue, etc.)
- Configurable health check strategies
- Pluggable deployment hooks
- Multi-environment support (dev/test/prod)

## Important Notes

1. **Dependency Requirements:**
   - Server needs Docker and Docker Compose installed
   - Requires curl command for health checks
   - Ensure sufficient disk space for multiple image versions

2. **Environment Configuration:**
   - Properly configure GitHub Secrets
   - Ensure stable SSH connections
   - Application needs to support root path health checks

3. **Monitoring Recommendations:**
   - Regularly check disk usage
   - Monitor container resource consumption
   - Pay attention to deployment logs and error messages

## Latest Modification Records

**2025-01-XX Major Updates:**
- Implemented complete zero-downtime blue-green deployment solution
- Optimized configuration file management, separated static configurations
- Enhanced rollback system with intelligent version selection
- Simplified port configuration, removed port 13000
- Improved health check mechanisms
- Established configuration synchronization system

## Implementation Details

### Switch Upstream Function Enhancement
**Before:** Hardcoded configuration content in script
**After:** File-based configuration switching
- Created separate `upstream-blue.conf` and `upstream-green.conf`
- `switch_upstream()` function now copies appropriate file to `upstream.conf`
- Cleaner, more maintainable approach

### Configuration Sync System
**Purpose:** Ensure all required config files exist on remote server
**Features:**
- Intelligent file comparison (only updates changed files)
- Directory structure creation
- Environment file initialization
- Executable permission management

### Multi-tag Image Strategy
**Tags Generated:**
- `latest`: Always points to newest build
- `{git-hash}`: 7-character commit hash for stable identification
- `{date_time}`: Timestamp-based version for chronological tracking

**Benefits:**
- Flexible rollback options
- Clear version identification
- Automated cleanup of old versions

## Error Handling and Recovery

### Deployment Failure Scenarios
1. **New container fails to start:** Automatic cleanup, no service disruption
2. **Health check timeout:** Rollback to previous configuration
3. **Nginx reload failure:** Restore backup configuration
4. **Network connectivity issues:** Retry mechanisms with exponential backoff

### Monitoring Integration Points
- Container health status monitoring
- Nginx access/error log analysis
- Deployment success/failure notifications
- Resource usage tracking

This comprehensive memory file captures all technical implementation details, design decisions, and operational procedures for future AI reference and continued development.