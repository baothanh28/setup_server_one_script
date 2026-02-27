#!/bin/bash

# ============================================
# Server Setup Script - DevOps Optimized
# Installs: PostgreSQL, Nginx, Docker, NginxUI
# Target OS: Ubuntu 22.04 / Debian / RHEL
# ============================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    log_error "Please run as root (use sudo)"
    exit 1
fi

# Check if .env file exists and fix line endings (CRLF to LF)
if [ ! -f ".env" ]; then
    log_error ".env file not found! Please create .env file from env.example"
    exit 1
else
    log_info "Sanitizing .env line endings..."
    sed -i 's/\r//' .env
fi

# Load environment variables safely
log_info "Loading configuration from .env file..."
set -a
source .env
set +a

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
else
    log_error "Cannot detect OS."
    exit 1
fi

log_info "Detected OS: $OS $VER"

# ============================================
# Fix PostgreSQL GPG Key Conflicts
# ============================================
fix_postgresql_gpg_conflict() {
    if [ "$OS" != "ubuntu" ] && [ "$OS" != "debian" ]; then
        return 0
    fi
    
    log_info "Cleaning up potential GPG and Repository conflicts..."
    
    # Remove files causing "Conflicting values set for option Signed-By"
    rm -f /etc/apt/keyrings/postgresql.gpg
    rm -f /etc/apt/sources.list.d/pgdg.list
    rm -f /etc/apt/sources.list.d/postgresql.list

    if [ -f "/etc/apt/sources.list" ]; then
        sed -i '/apt.postgresql.org/d' /etc/apt/sources.list
    fi
}

# ============================================
# Install PostgreSQL
# ============================================
install_postgresql() {
    log_info "Installing PostgreSQL..."
    POSTGRES_VER=${POSTGRES_VERSION:-17} 

    if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        fix_postgresql_gpg_conflict
        apt-get update -y
        apt-get install -y wget ca-certificates gnupg lsb-release postgresql-common
        
        # Use 'yes' to skip the manual confirmation prompt
        yes "" | /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh
        
        apt-get update -y
        apt-get install -y postgresql-${POSTGRES_VER} postgresql-contrib-${POSTGRES_VER}

    elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ]; then
        yum install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-$(rpm -E %{rhel})-x86_64/pgdg-redhat-repo-latest.noarch.rpm
        yum install -y postgresql${POSTGRES_VER}-server postgresql${POSTGRES_VER}-contrib
        /usr/pgsql-${POSTGRES_VER}/bin/postgresql-${POSTGRES_VER}-setup initdb
    fi
    
    systemctl enable postgresql
    systemctl start postgresql
    
    # Database Configuration
    if [ -n "$POSTGRES_PASSWORD" ]; then
        sudo -u postgres psql -c "ALTER USER postgres PASSWORD '$POSTGRES_PASSWORD';" || true
    fi

    if [ -n "$POSTGRES_DB" ] && [ -n "$POSTGRES_USER" ]; then
        sudo -u postgres psql -c "CREATE USER $POSTGRES_USER WITH PASSWORD '$POSTGRES_PASSWORD';" || true
        sudo -u postgres psql -c "CREATE DATABASE $POSTGRES_DB OWNER $POSTGRES_USER;" || true
    fi

    if [ "$POSTGRES_ALLOW_REMOTE" = "true" ]; then
        PG_CONF=$(find /etc/postgresql/ -name "postgresql.conf" | head -n 1)
        PG_HBA=$(find /etc/postgresql/ -name "pg_hba.conf" | head -n 1)
        
        if [ -n "$PG_CONF" ]; then
            sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" "$PG_CONF"
            echo "host all all 0.0.0.0/0 md5" >> "$PG_HBA"
            systemctl restart postgresql
        fi
    fi
    log_info "PostgreSQL setup complete."
}

# ============================================
# Install Nginx
# ============================================
install_nginx() {
    log_info "Installing Nginx..."
    if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        apt-get install -y nginx
    else
        yum install -y nginx
    fi
    systemctl enable nginx
    systemctl start nginx
}

# ============================================
# Install Docker
# ============================================
install_docker() {
    log_info "Installing Docker..."
    if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        apt-get install -y ca-certificates curl gnupg
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/${OS}/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes
        chmod a+r /etc/apt/keyrings/docker.gpg
        
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${OS} $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt-get update -y
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    else
        yum install -y yum-utils
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        yum install -y docker-ce docker-ce-cli containerd.io
    fi
    systemctl enable docker
    systemctl start docker
}

# ============================================
# Install NginxUI using Docker Compose
# ============================================
install_nginxui() {
    log_info "Setting up NginxUI with Docker Compose..."
    
    # Check if docker-compose.yml exists
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
    
    if [ ! -f "$COMPOSE_FILE" ]; then
        log_error "docker-compose.yml file not found at $COMPOSE_FILE"
        exit 1
    fi
    
    # Check if Docker is running
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running. Please start Docker first."
        exit 1
    fi
    
    # Check if docker compose is available
    if docker compose version &> /dev/null; then
        COMPOSE_CMD="docker compose"
    elif command -v docker-compose &> /dev/null; then
        COMPOSE_CMD="docker-compose"
    else
        log_error "Docker Compose is not installed. Please install Docker Compose first."
        exit 1
    fi
    
    # Create nginx-ui data directory if it doesn't exist
    log_info "Creating nginx-ui data directory..."
    mkdir -p "$SCRIPT_DIR/nginx-ui/data"
    
    # Change to script directory and start the container
    cd "$SCRIPT_DIR"
    log_info "Starting NginxUI container..."
    $COMPOSE_CMD up -d
    
    # Wait a moment for container to start
    sleep 2
    
    # Check if container is running
    if docker ps | grep -q nginx-ui; then
        log_info "NginxUI container is running successfully!"
        log_info "NginxUI Access: http://$(hostname -I | awk '{print $1}'):${NGINXUI_PORT:-9000}"
    else
        log_warn "NginxUI container may not be running. Check logs with: $COMPOSE_CMD logs nginx-ui"
    fi
    
    log_info "NginxUI setup complete."
}

# ============================================
# Main Execution Flow
# ============================================
main() {
    log_info "Starting full system setup..."
    log_info "--------------------------------------------"
    
    [ "$INSTALL_POSTGRESQL" != "false" ] && install_postgresql
    [ "$INSTALL_NGINX" != "false" ] && install_nginx
    [ "$INSTALL_DOCKER" != "false" ] && install_docker
    [ "$INSTALL_NGINXUI" != "false" ] && install_nginxui

    log_info "--------------------------------------------"
    log_info "All tasks finished successfully!"
    log_info "--------------------------------------------"
}

main