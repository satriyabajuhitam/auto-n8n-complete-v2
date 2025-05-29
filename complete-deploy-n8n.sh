#!/bin/bash

# Hi there, future automation wizard! 👋
# Let's get your N8N up and running with PostgreSQL, ffmpeg, yt-dlp, puppeteer & caddy. ✨
echo "============================================================================"
echo "               n8n, PostgreSQL, ffmpeg, yt-dlp, puppeteer & caddy           "
echo "                          ~ by @satriyabajuhitam ~                          "
echo "============================================================================"

# First things first: Are you root?
if [[ $EUID -ne 0 ]]; then
   echo "Hold up! ✋ This script needs root powers (sudo). Run it with 'sudo ./install_n8n_postgres_fixed.sh' to let me do my magic! 🧙‍♂️"
   exit 1
fi

# Function to set up swap memory for low-memory systems
setup_swap() {
    echo ""
    echo "💨 Checking server's memory. Setting up swap space if needed..."
    
    if [ "$(swapon --show | wc -l)" -gt 1 ]; then
        SWAP_SIZE_HUMAN=$(free -h | grep Swap | awk '{print $2}')
        echo "✅ Swap already enabled with size ${SWAP_SIZE_HUMAN}."
        return
    fi
    
    RAM_MB=$(free -m | grep Mem | awk '{print $2}')
    
    local SWAP_SIZE_MB
    if [ "$RAM_MB" -le 2048 ]; then
        SWAP_SIZE_MB=$((RAM_MB * 2))
    elif [ "$RAM_MB" -gt 2048 ] && [ "$RAM_MB" -le 8192 ]; then
        SWAP_SIZE_MB=$RAM_MB
    else
        SWAP_SIZE_MB=4096
    fi
    
    local SWAP_GB=$(( (SWAP_SIZE_MB + 1023) / 1024 ))
    
    echo "Setting up a ${SWAP_GB}GB (${SWAP_SIZE_MB}MB) swap file... ⏳"
    
    if command -v fallocate &> /dev/null; then
        if ! fallocate -l ${SWAP_SIZE_MB}M /swapfile; then
            echo "⚠️ fallocate failed. Using 'dd' instead..."
            if ! dd if=/dev/zero of=/swapfile bs=1M count=$SWAP_SIZE_MB status=progress; then
                echo "❌ Fatal: Couldn't create swap file. Check disk space!"
                exit 1
            fi
        fi
    else
        echo "No fallocate. Using 'dd' to create swap file..."
        if ! dd if=/dev/zero of=/swapfile bs=1M count=$SWAP_SIZE_MB status=progress; then
            echo "❌ Fatal: Couldn't create swap file. Check disk space!"
            exit 1
        fi
    fi
    
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    
    if ! grep -q "/swapfile" /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi
    
    sysctl vm.swappiness=10
    sysctl vm.vfs_cache_pressure=50
    
    if ! grep -q "vm.swappiness" /etc/sysctl.conf; then
        echo "vm.swappiness=10" >> /etc/sysctl.conf
    fi
    
    if ! grep -q "vm.vfs_cache_pressure" /etc/sysctl.conf; then
        echo "vm.vfs_cache_pressure=50" >> /etc/sysctl.conf
    fi
    
    echo "🎉 Swap setup complete! ${SWAP_GB}GB swap ready."
}

# Show help message
show_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -h, --help      Display this help message"
    echo "  -d, --dir DIR   Set N8N's home directory (default: /home/n8n)"
    echo "  -s, --skip-docker Skip Docker installation"
    exit 0
}

# Parse command-line arguments
N8N_DIR="/home/n8n"
SKIP_DOCKER=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -d|--dir)
            N8N_DIR="$2"
            shift 2
            ;;
        -s|--skip-docker)
            SKIP_DOCKER=true
            shift
            ;;
        *)
            echo "❓ Unknown option '$1'. Here's what I know:"
            show_help
            ;;
    esac
done

# Check if domain resolves to server IP
check_domain() {
    local domain=$1
    local server_ip=$(hostname -I | awk '{print $1}' || curl -s --max-time 10 https://api.ipify.org)
    if [ -z "$server_ip" ]; then
        echo "❌ Couldn't get server's public IP. Check your network!"
        return 1
    fi
    local domain_ip=$(dig +short "$domain" A)
    if [ "$domain_ip" = "$server_ip" ]; then
        return 0
    else
        return 1
    fi
}

# Install base dependencies
install_base_dependencies() {
    echo ""
    echo "Updating tools and installing essentials... 🔄"
    
    # Switch to main Ubuntu archive to avoid azure.archive.ubuntu.com issues
    sed -i 's/azure.archive.ubuntu.com/archive.ubuntu.com/g' /etc/apt/sources.list
    
    # Clean and update APT cache
    apt-get clean
    rm -rf /var/lib/apt/lists/*
    
    # Retry logic for apt-get update
    for i in {1..3}; do
        echo "Attempt $i of 3 to update package lists..."
        if apt-get update -y; then
            echo "✅ Package lists updated!"
            break
        else
            echo "⚠️ Attempt $i failed. Retrying in 5 seconds..."
            sleep 5
        fi
    done
    if [ $i -eq 4 ]; then
        echo "❌ Failed to update package lists after 3 attempts. Check network or apt sources!"
        exit 1
    fi
    
    # Ensure universe repository is enabled
    add-apt-repository universe -y
    
    # Retry logic for package installation
    for i in {1..3}; do
        echo "Attempt $i of 3 to install packages..."
        if apt-get install -y dnsutils curl cron jq tar gzip python3-full python3-venv pipx net-tools bc postgresql-client; then
            echo "✅ Essential tools, including PostgreSQL client, installed!"
            return 0
        else
            echo "⚠️ Attempt $i failed. Retrying in 5 seconds..."
            sleep 5
        fi
    done
    echo "❌ Failed to install packages after 3 attempts. Check internet, apt sources, or disk space!"
    echo "Run 'sudo apt-get install -y --debug dnsutils curl cron jq tar gzip python3-full python3-venv pipx net-tools bc postgresql-client' for detailed errors."
    exit 1
}

# Install Docker and Docker Compose
install_docker() {
    echo ""
    if $SKIP_DOCKER && command -v docker &> /dev/null; then
        echo "Docker already installed, skipping as requested. 😎"
        return
    fi

    if command -v docker &> /dev/null; then
        echo "Docker is already installed. 👍"
    else
        echo "Installing Docker... ⏳"
        apt-get update
        apt-get install -y apt-transport-https ca-certificates curl software-properties-common
        mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt-get update
        apt-get install -y docker-ce docker-ce-cli containerd.io
        if [ $? -ne 0 ]; then
            echo "❌ Docker installation failed! Check errors and network."
            exit 1
        fi
        echo "✅ Docker engine installed!"
    fi

    if command -v docker-compose &> /dev/null || (command -v docker &> /dev/null && docker compose version &> /dev/null); then
        echo "Docker Compose is ready. 🚀"
    else
        echo "Installing Docker Compose plugin... ⚙️"
        apt-get install -y docker-compose-plugin
        if ! (command -v docker &> /dev/null && docker compose version &> /dev/null); then
            echo "⚠️ Docker Compose plugin failed. Trying older package..."
            apt-get install -y docker-compose
        fi
        echo "✅ Docker Compose installed!"
    fi

    if ! command -v docker &> /dev/null; then
        echo "❌ Docker not found. Installation issue."
        exit 1
    fi

    if ! command -v docker-compose &> /dev/null && ! (command -v docker &> /dev/null && docker compose version &> /dev/null); then
        echo "❌ Docker Compose not installed correctly."
        exit 1
    fi

    if [ "$SUDO_USER" != "" ]; then
        echo "Adding user '$SUDO_USER' to docker group... 🧑‍💻"
        usermod -aG docker "$SUDO_USER"
    fi
    systemctl enable docker
    systemctl restart docker
    echo "🎉 Docker and Compose ready!"
}

# Install yt-dlp
install_yt_dlp() {
    echo ""
    echo "Installing yt-dlp... ✨"
    if command -v pipx &> /dev/null; then
        pipx install yt-dlp
        pipx ensurepath
        echo "✅ yt-dlp installed via pipx."
    else
        echo "Installing yt-dlp in a virtual environment..."
        python3 -m venv /opt/yt-dlp-venv
        /opt/yt-dlp-venv/bin/pip install -U pip yt-dlp
        ln -sf /opt/yt-dlp-venv/bin/yt-dlp /usr/local/bin/yt-dlp
        chmod +x /usr/local/bin/yt-dlp
        echo "✅ yt-dlp installed and symlinked!"
    fi
    export PATH="$PATH:/usr/local/bin:/opt/yt-dlp-venv/bin:$HOME/.local/bin"
}

# Ensure cron is running
ensure_cron_running() {
    echo ""
    echo "Checking cron service... 💖"
    systemctl enable cron
    systemctl start cron
    if systemctl is-active --quiet cron; then
        echo "✅ Cron is active and enabled."
    else
        echo "⚠️ Cron service not active. Automated tasks may not work."
    fi
}

# --- Main execution ---
setup_swap
install_base_dependencies
install_docker
install_yt_dlp
ensure_cron_running

echo ""
read -p "What's the domain for N8N (e.g., n8n.example.com)? 👇 " DOMAIN
while ! check_domain "$DOMAIN"; do
    SERVER_IP=$(hostname -I | awk '{print $1}' || curl -s --max-time 10 https://api.ipify.org)
    echo "❌ Domain '$DOMAIN' isn't pointing to this server's IP ($SERVER_IP)."
    echo "   Update your DNS to point '$DOMAIN' to '$SERVER_IP'."
    read -p "Hit Enter after updating DNS, or enter a new domain: " NEW_DOMAIN
    if [ -n "$NEW_DOMAIN" ]; then
        DOMAIN="$NEW_DOMAIN"
    fi
done
echo "✅ '$DOMAIN' is pointing correctly!"

echo ""
echo "Creating directory structure at '$N8N_DIR'... "
mkdir -p "$N8N_DIR"
mkdir -p "$N8N_DIR/files"
mkdir -p "$N8N_DIR/files/temp"
mkdir -p "$N8N_DIR/files/youtube_data"
mkdir -p "$N8N_DIR/files/backup_full"
echo "✅ Directories set!"

echo ""
echo "Creating Dockerfile... "
cat << 'EOF_DOCKERFILE' > "$N8N_DIR/Dockerfile"
FROM n8nio/n8n:latest
USER root
RUN apk update && \
    apk add --no-cache ffmpeg wget zip unzip python3 py3-pip jq tar gzip \
    chromium nss freetype freetype-dev harfbuzz ca-certificates ttf-freefont \
    font-noto font-noto-cjk font-noto-emoji dbus udev
RUN pip3 install --break-system-packages -U yt-dlp && \
    chmod +x /usr/bin/yt-dlp
RUN npm install -g n8n-nodes-puppeteer
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true \
    PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser
RUN mkdir -p /files/youtube_data /files/backup_full /files/temp && \
    chown -R node:node /files
USER node
WORKDIR /home/node
EOF_DOCKERFILE
echo "✅ Dockerfile created!"

echo ""
echo "Generating docker-compose.yml with PostgreSQL... "
POSTGRES_PASSWORD=$(openssl rand -base64 12)
cat << 'EOF_COMPOSE' > "$N8N_DIR/docker-compose.yml"
services:
  n8n:
    build:
      context: .
      dockerfile: Dockerfile
    image: n8n-custom-ffmpeg:latest
    restart: always
    ports:
      - "127.0.0.1:5678:5678"
    environment:
      - N8N_HOST=__N8N_HOST_PLACEHOLDER__
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - NODE_ENV=production
      - WEBHOOK_URL=https://__N8N_HOST_PLACEHOLDER__
      - GENERIC_TIMEZONE=Asia/Jakarta
      - N8N_DEFAULT_BINARY_DATA_MODE=filesystem
      - N8N_BINARY_DATA_STORAGE=/files
      - N8N_DEFAULT_BINARY_DATA_FILESYSTEM_DIRECTORY=/files
      - N8N_DEFAULT_BINARY_DATA_TEMP_DIRECTORY=/files/temp
      - NODE_FUNCTION_ALLOW_BUILTIN=child_process,path,fs,util,os
      - N8N_EXECUTIONS_DATA_MAX_SIZE=304857600
      - PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
      - PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser
      - DB_TYPE=postgresdb
      - DB_POSTGRES_HOST=postgres
      - DB_POSTGRES_PORT=5432
      - DB_POSTGRES_DATABASE=n8n
      - DB_POSTGRES_USER=n8n
      - DB_POSTGRES_PASSWORD=__POSTGRES_PASSWORD_PLACEHOLDER__
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
      #- N8N_RUNNERS_ENABLED=true
      #- N8N_RUNNERS_MODE=internal
    volumes:
      - __N8N_DIR_PLACEHOLDER__:/home/node/.n8n
      - __N8N_DIR_PLACEHOLDER__/files:/files
    user: "node"
    cap_add:
      - SYS_ADMIN
    depends_on:
      postgres:
        condition: service_healthy

  postgres:
    image: postgres:16
    restart: always
    environment:
      - POSTGRES_USER=n8n
      - POSTGRES_PASSWORD=__POSTGRES_PASSWORD_PLACEHOLDER__
      - POSTGRES_DB=n8n
      - PGDATA=/var/lib/postgresql/data/pgdata
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U n8n"]
      interval: 5s
      timeout: 5s
      retries: 10
    mem_limit: 512m
    cpus: 0.5
    command: postgres -c max_connections=20 -c shared_buffers=64MB -c effective_cache_size=192MB

  caddy:
    image: caddy:latest
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - __N8N_DIR_PLACEHOLDER__/Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config
    depends_on:
      - n8n

volumes:
  caddy_data:
  caddy_config:
  postgres_data:
EOF_COMPOSE

sed -i "s|__N8N_HOST_PLACEHOLDER__|${DOMAIN}|g" "$N8N_DIR/docker-compose.yml"
sed -i "s|__N8N_DIR_PLACEHOLDER__|${N8N_DIR}|g" "$N8N_DIR/docker-compose.yml"
sed -i "s|__POSTGRES_PASSWORD_PLACEHOLDER__|${POSTGRES_PASSWORD}|g" "$N8N_DIR/docker-compose.yml"
echo "PostgreSQL password: ${POSTGRES_PASSWORD}" > "$N8N_DIR/postgres_password.txt"
chmod 600 "$N8N_DIR/postgres_password.txt"
chown 1000:1000 "$N8N_DIR/postgres_password.txt"
echo "✅ docker-compose.yml with PostgreSQL ready! Password saved to $N8N_DIR/postgres_password.txt"

echo ""
echo "Setting up Caddyfile... 🔒"
read -p "Do you want a Let's Encrypt SSL certificate? (y/n): " USE_LETSENCRYPT_SSL

CADDYFILE_TLS_CONFIG="tls internal"
if [[ "$USE_LETSENCRYPT_SSL" =~ ^[Yy]$ ]]; then
    read -p "Enter your email for Let's Encrypt: " LETSENCRYPT_EMAIL
    if [ -n "$LETSENCRYPT_EMAIL" ]; then
        CADDYFILE_TLS_CONFIG="tls ${LETSENCRYPT_EMAIL}"
        echo "Using Let's Encrypt with email: ${LETSENCRYPT_EMAIL}."
        echo "⚠️ Ensure ports 80 and 443 are open!"
    else
        echo "No email provided, using internal TLS certificate."
    fi
else
    echo "Using internal TLS certificate. Expect a browser warning."
fi

cat << EOF_CADDY > "$N8N_DIR/Caddyfile"
${DOMAIN} {
    reverse_proxy n8n:5678
    ${CADDYFILE_TLS_CONFIG}
}
EOF_CADDY
echo "✅ Caddyfile set!"

echo ""
echo "Creating backup script for workflows, credentials, and PostgreSQL... "
cat << 'EOF_BACKUP_SCRIPT' > "$N8N_DIR/backup-workflows.sh"
#!/bin/bash

N8N_DIR_VALUE="__N8N_DIR_VALUE__"
BACKUP_BASE_DIR="${N8N_DIR_VALUE}/files/backup_full"
LOG_FILE="${BACKUP_BASE_DIR}/backup.log"
DOMAIN_NAME="__DOMAIN_NAME__"

DATE="$(date +"%Y%m%d_%H%M%S")"
BACKUP_FILE_NAME="n8n_backup_${DATE}.tar.gz"
BACKUP_FILE_PATH="${BACKUP_BASE_DIR}/${BACKUP_FILE_NAME}"
TEMP_DIR_HOST="/tmp/n8n_backup_host_${DATE}"
TEMP_DIR_CONTAINER_BASE="/tmp/n8n_workflow_exports"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

mkdir -p "${BACKUP_BASE_DIR}"
log "Starting N8N and PostgreSQL backup for domain: ${DOMAIN_NAME}..."

N8N_CONTAINER_NAME_PATTERN="n8n"
POSTGRES_CONTAINER_NAME_PATTERN="postgres"
N8N_CONTAINER_ID="$(docker ps -q --filter "name=${N8N_CONTAINER_NAME_PATTERN}" --format '{{.ID}}' | head -n 1)"
POSTGRES_CONTAINER_ID="$(docker ps -q --filter "name=${POSTGRES_CONTAINER_NAME_PATTERN}" --format '{{.ID}}' | head -n 1)"

if [ -z "${N8N_CONTAINER_ID}" ]; then
    log "Error: No running N8N container. Backup failed. 😞"
    exit 1
fi
if [ -z "${POSTGRES_CONTAINER_ID}" ]; then
    log "Error: No running PostgreSQL container. Backup failed. 😞"
    exit 1
fi
log "Found N8N container ID: ${N8N_CONTAINER_ID}"
log "Found PostgreSQL container ID: ${POSTGRES_CONTAINER_ID}"

mkdir -p "${TEMP_DIR_HOST}/workflows"
mkdir -p "${TEMP_DIR_HOST}/credentials"

TEMP_DIR_CONTAINER_UNIQUE="${TEMP_DIR_CONTAINER_BASE}/export_${DATE}"
docker exec "${N8N_CONTAINER_ID}" mkdir -p "${TEMP_DIR_CONTAINER_UNIQUE}"

log "Exporting workflows to ${TEMP_DIR_CONTAINER_UNIQUE}..."
WORKFLOWS_JSON="$(docker exec "${N8N_CONTAINER_ID}" n8n list:workflow --json 2>>"$LOG_FILE")"

if [ -z "${WORKFLOWS_JSON}" ] || [ "${WORKFLOWS_JSON}" == "[]" ]; then
    log "Warning: No workflows found. Is your N8N new? 🤔"
else
    echo "${WORKFLOWS_JSON}" | jq -c '.[]' | while IFS= read -r workflow_data; do
        id="$(echo "${workflow_data}" | jq -r '.id')"
        name="$(echo "${workflow_data}" | jq -r '.name' | tr -dc '[:alnum:][:space:]_-' | tr '[:space:]' '_')"
        safe_name="$(echo "${name}" | sed 's/[^a-zA-Z0-9_-]/_/g' | cut -c1-100)"
        output_file_container="${TEMP_DIR_CONTAINER_UNIQUE}/${id}-${safe_name}.json"
        log "Exporting workflow: '${name}' (ID: ${id}) to ${output_file_container}"
        if docker exec "${N8N_CONTAINER_ID}" n8n export:workflow --id="${id}" --output="${output_file_container}" >>"$LOG_FILE" 2>&1; then
            log "Successfully exported workflow ID ${id}. 👍"
        else
            log "Error exporting workflow ID ${id}. Check container logs! 🕵️‍♀️"
        fi
    done

    log "Copying workflows to host..."
    if docker cp "${N8N_CONTAINER_ID}:${TEMP_DIR_CONTAINER_UNIQUE}/." "${TEMP_DIR_HOST}/workflows/"; then
        log "Workflows copied successfully! 🎉"
    else
        log "Error copying workflows to host. 😞"
    fi
fi

log "Backing up PostgreSQL database..."
PG_BACKUP_FILE="${TEMP_DIR_HOST}/credentials/n8n_database_backup_${DATE}.sql"
if docker exec "${POSTGRES_CONTAINER_ID}" pg_dump -U n8n n8n > "${PG_BACKUP_FILE}"; then
    log "Backed up PostgreSQL database to ${PG_BACKUP_FILE}. 😌"
else
    log "Error: Failed to back up PostgreSQL database. Check logs! 😞"
fi

KEY_PATH_HOST="${N8N_DIR_VALUE}/encryptionKey"
if [ -f "${KEY_PATH_HOST}" ]; then
    cp "${KEY_PATH_HOST}" "${TEMP_DIR_HOST}/credentials/encryptionKey"
    log "Backed up encryptionKey. ✨"
else
    log "Warning: encryptionKey not found at ${KEY_PATH_HOST}. Skipping. 😬"
fi

log "Creating compressed backup: ${BACKUP_FILE_PATH}..."
if tar -czf "${BACKUP_FILE_PATH}" -C "${TEMP_DIR_HOST}" . ; then
    log "Backup file '${BACKUP_FILE_NAME}' created! ✅"
else
    log "❌ Couldn't create backup file '${BACKUP_FILE_PATH}'. Disk space issue? 📉"
fi

log "Cleaning up temporary directories..."
rm -rf "${TEMP_DIR_HOST}"
docker exec "${N8N_CONTAINER_ID}" rm -rf "${TEMP_DIR_CONTAINER_UNIQUE}"

log "Keeping 30 most recent backups in ${BACKUP_BASE_DIR}..."
find "${BACKUP_BASE_DIR}" -maxdepth 1 -name 'n8n_backup_*.tar.gz' -type f -printf '%T@ %p\n' | \
sort -nr | tail -n +31 | cut -d' ' -f2- | xargs -r rm -f

log "Backup completed! Your N8N is safe. 💖"

exit 0
EOF_BACKUP_SCRIPT

sed -i \
    -e "s|__N8N_DIR_VALUE__|${N8N_DIR}|g" \
    -e "s|__DOMAIN_NAME__|${DOMAIN}|g" \
    "$N8N_DIR/backup-workflows.sh"
chmod +x "$N8N_DIR/backup-workflows.sh"
echo "✅ Backup script for PostgreSQL created!"

echo ""
echo "Adjusting folder permissions for N8N and PostgreSQL... "
sudo chown -R 1000:1000 "$N8N_DIR"
sudo chmod -R u+rwX,g+rX,o+rX "$N8N_DIR"
sudo chown -R 1000:1000 "$N8N_DIR/files"
sudo chmod -R u+rwX,g+rX,o+rX "$N8N_DIR/files"
docker volume create postgres_data
docker run --rm -v postgres_data:/var/lib/postgresql/data alpine chown -R 999:999 /var/lib/postgresql/data
echo "✅ Permissions for N8N and PostgreSQL set!"

echo ""
echo "Building and starting N8N, PostgreSQL, and Caddy... ☕"
cd "$N8N_DIR"

local DOCKER_COMPOSE_CMD
if command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker-compose"
elif command -v docker &> /dev/null && docker compose version &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker compose"
else
    echo "❌ Can't find docker-compose or plugin. Installation issue. 😟"
    exit 1
fi

echo "Stopping any existing containers..."
$DOCKER_COMPOSE_CMD down > /dev/null 2>&1 || true

echo "Building custom N8N image with cache..."
if ! $DOCKER_COMPOSE_CMD build n8n; then
    echo "❌ Docker build failed. Check Dockerfile errors. 🐛"
    exit 1
fi
echo "✅ Docker image built!"

echo "Starting containers..."
if ! $DOCKER_COMPOSE_CMD up -d; then
    echo "❌ Container startup failed. Check logs: '$DOCKER_COMPOSE_CMD logs'. 😔"
    exit 1
fi
echo "✅ Containers starting! Waiting up to 5 minutes for full startup..."
for i in {1..30}; do
    sleep 10
    if $DOCKER_COMPOSE_CMD ps | grep -q "n8n.* Up" && \
       $DOCKER_COMPOSE_CMD ps | grep -q "postgres.* Up" && \
       $DOCKER_COMPOSE_CMD ps | grep -q "caddy.* Up"; then
        echo "🎉 All containers are up!"
        break
    fi
    echo "Still waiting... ($((i*10)) seconds elapsed)"
done
if [ $i -eq 30 ]; then
    echo "⚠️ Timeout after 5 minutes. Check logs: '$DOCKER_COMPOSE_CMD logs'."
fi

echo "Checking initial logs for debugging..."
$DOCKER_COMPOSE_CMD logs --tail=20 n8n
$DOCKER_COMPOSE_CMD logs --tail=20 postgres
$DOCKER_COMPOSE_CMD logs --tail=20 caddy

echo ""
echo "Setting up auto-update script... 🆕"
cat << 'EOF_UPDATE_SCRIPT' > "$N8N_DIR/update-n8n.sh"
#!/bin/bash
N8N_DIR_VALUE="__N8N_DIR_VALUE__"
LOG_FILE="${N8N_DIR_VALUE}/update.log"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"; }
log "Starting N8N update check..."
cd "${N8N_DIR_VALUE}"

local DOCKER_COMPOSE_CMD
if command -v docker-compose &> /dev/null; then DOCKER_COMPOSE_CMD="docker-compose";
elif command -v docker &> /dev/null && docker compose version &> /dev/null; then DOCKER_COMPOSE_CMD="docker compose";
else log "Error: Docker Compose not found. Cannot update. 😥"; exit 1; fi

log "Updating yt-dlp on host..."
if command -v pipx &> /dev/null; then pipx upgrade yt-dlp >> "$LOG_FILE" 2>&1;
elif [ -d "/opt/yt-dlp-venv" ]; then /opt/yt-dlp-venv/bin/pip install -U yt-dlp >> "$LOG_FILE" 2>&1; fi
log "yt-dlp on host updated!"

log "Pulling latest N8N and PostgreSQL images..."
docker pull n8nio/n8n:latest >> "$LOG_FILE" 2>&1
docker pull postgres:16 >> "$LOG_FILE" 2>&1

CURRENT_CUSTOM_IMAGE_ID="$(${DOCKER_COMPOSE_CMD} images -q n8n)"
log "Building custom N8N image..."
if ! ${DOCKER_COMPOSE_CMD} build n8n >> "$LOG_FILE" 2>&1; then
    log "Error: Failed to build image. Update aborted. 🐛"
    exit 1
fi
NEW_CUSTOM_IMAGE_ID="$(${DOCKER_COMPOSE_CMD} images -q n8n)"

if [ "${CURRENT_CUSTOM_IMAGE_ID}" != "${NEW_CUSTOM_IMAGE_ID}" ]; then
    log "New N8N version detected! Updating..."
    log "Running backup before update..."
    if [ -x "${N8N_DIR_VALUE}/backup-workflows.sh" ]; then
        "${N8N_DIR_VALUE}/backup-workflows.sh" >> "$LOG_FILE" 2>&1
    else
        log "Warning: Backup script not found. Skipping backup. 🤞"
    fi
    log "Restarting containers..."
    ${DOCKER_COMPOSE_CMD} down >> "$LOG_FILE" 2>&1
    ${DOCKER_COMPOSE_CMD} up -d n8n postgres caddy >> "$LOG_FILE" 2>&1
    log "N8N update completed! 🎉"
else
    log "No new N8N updates. You're up to date! 👍"
fi

log "Updating yt-dlp in N8N container..."
N8N_CONTAINER_FOR_UPDATE="$(${DOCKER_COMPOSE_CMD} ps -q n8n)"
if [ -n "${N8N_CONTAINER_FOR_UPDATE}" ]; then
    docker exec -u root "${N8N_CONTAINER_FOR_UPDATE}" pip3 install --break-system-packages -U yt-dlp >> "$LOG_FILE" 2>&1
    log "yt-dlp in container updated!"
else
    log "Warning: No N8N container found for yt-dlp update. 🤷‍♀️"
fi
log "Update check completed! ✨"
EOF_UPDATE_SCRIPT

sed -i "s|__N8N_DIR_VALUE__|${N8N_DIR}|g" "$N8N_DIR/update-n8n.sh"
chmod +x "$N8N_DIR/update-n8n.sh"
echo "✅ Auto-update script created!"

echo ""
echo "Setting up cron jobs for updates every 12 hours and backups at 2 AM..."
CRON_USER=$(whoami)
UPDATE_CRON="0 */12 * * * ${N8N_DIR}/update-n8n.sh"
BACKUP_CRON="0 2 * * * ${N8N_DIR}/backup-workflows.sh"
(crontab -u "$CRON_USER" -l 2>/dev/null | grep -v "update-n8n.sh" | grep -v "backup-workflows.sh"; echo "$UPDATE_CRON"; echo "$BACKUP_CRON") | crontab -u "$CRON_USER" -
echo "✅ Cron jobs configured!"

echo ""
echo "Cleaning up old SQLite database (if exists)..."
if [ -f "$N8N_DIR/database.sqlite" ]; then
    rm "$N8N_DIR/database.sqlite"
    echo "✅ Removed old SQLite database."
else
    echo "✅ No SQLite database found."
fi

echo "======================================================================"
echo "🎉 Hooray! Your N8N adventure with PostgreSQL is ready! 🎉"
echo "wait a few minutes ( 3 minute ) and then visit your N8N instance at:"
echo "👉 https://${DOMAIN}"
if [ "$(swapon --show | wc -l)" -gt 1 ]; then
    SWAP_INFO=$(free -h | grep Swap | awk '{print $2}')
    echo "► Swap configured: ${SWAP_INFO} ✅"
fi
echo "► Database: Using PostgreSQL for reliability! 🗄️"
echo "► PostgreSQL password saved in: '$N8N_DIR/postgres_password.txt' (keep it safe!) 🔑"
echo "► All N8N configuration and data stored in: '$N8N_DIR' 📂"
echo "► PostgreSQL data stored in Docker volume: 'postgres_data' 🗃️"
echo "► Automatic updates every 12 hours. Log: '$N8N_DIR/update.log' 🔄"
echo "► Backup feature (workflows, credentials, PostgreSQL):"
echo "  - Daily backup at 2 AM. ⏰"
echo "  - Backups stored: '$N8N_DIR/files/backup_full/n8n_backup_YYYYMMDD_HHMMSS.tar.gz' 💾"
echo "  - Includes workflows, encryptionKey, and PostgreSQL dump. 🗄️"
echo "  - Keeps 30 most recent backups. 🗑️"
echo "  - Backup log: '$N8N_DIR/files/backup_full/backup.log' 📝"
echo "► YouTube video download directory: $N8N_DIR/files/youtube_data/ 🎬"
echo "► Puppeteer set up for web scraping! ✨"
echo ""
echo "Note: To use 'yt-dlp' from the command line, add '~/.local/bin' to your PATH."
echo "To restore a backup:"
echo "  1. Extract: tar -xzf /path/to/n8n_backup_*.tar.gz -C /tmp/restore"
echo "  2. Restore DB: docker exec -i <postgres_container_id> psql -U n8n -d n8n < /tmp/restore/credentials/n8n_database_backup_*.sql"
echo "  3. Restore workflows: Use n8n import commands."
echo "======================================================================"
echo "Enjoy your N8N journey with PostgreSQL! Questions? Just ask! 😊"
