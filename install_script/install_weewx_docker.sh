#!/bin/bash
set -euo pipefail

# ===== Settings ======================================================
TARGET_USER="${TARGET_USER:-$USER}"
REPO_URL="https://github.com/mmkk15/WeeWX-Docker.git"
REPO_DIR="WeeWX-Docker"
CONTAINER_NAME="weewx"
IMAGE_NAME="weewx"
TZ_DEFAULT="Europe/Berlin"
HTTP_PORT="80"
BACKUP_DIR="/var/backups/weewx"
IMAGE_BACKUP_NAME="weewx-image.tar"       # latest image
IMAGE_BACKUP_DATEFMT="%Y%m%d"

echo "Using user:        ${TARGET_USER}"
echo "Repository:        ${REPO_URL}"
echo "Target directory:  ${REPO_DIR}"
echo "Container name:    ${CONTAINER_NAME}"
echo "Image name:        ${IMAGE_NAME}"
echo "Timezone default:  ${TZ_DEFAULT}"
echo "HTTP port:         ${HTTP_PORT}"
echo "Backup directory:  ${BACKUP_DIR}"
echo

# ===== 1. Ensure git is installed ===================================
if ! command -v git >/dev/null 2>&1; then
  echo "Git is not installed. Installing..."
  sudo apt-get update
  sudo apt-get install -y git
fi

# ===== 2. Install Docker if needed ==================================
if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is not installed. Installing..."

  curl -fsSL https://get.docker.com -o get-docker.sh
  sudo sh get-docker.sh
fi

# Ensure Docker daemon is running
if ! systemctl is-active --quiet docker; then
  echo "Starting Docker service..."
  sudo systemctl start docker
fi

# ===== 3. Add user to docker group =================================
if id -nG "${TARGET_USER}" | grep -qw docker; then
  echo "User '${TARGET_USER}' is already in the docker group."
else
  echo "Adding '${TARGET_USER}' to docker group..."
  sudo usermod -aG docker "${TARGET_USER}"
  echo "NOTE: '${TARGET_USER}' must log out and back in for group change to take effect."
fi

# ===== 4. Clone or update your WeeWX-Docker repo ====================
if [ ! -d "${REPO_DIR}" ]; then
  echo "Cloning WeeWX-Docker repository..."
  git clone "${REPO_URL}" "${REPO_DIR}"
else
  echo "Repository already exists. Updating..."
  (
    cd "${REPO_DIR}"
    git pull --rebase || echo "Warning: could not pull latest changes."
  )
fi

cd "${REPO_DIR}"

# Make sure config dir exists (where weewx.conf, archive etc. live on host)
mkdir -p config

# ===== 5. Build WeeWX Docker image =================================
echo "Building WeeWX Docker image '${IMAGE_NAME}'..."
docker build -t "${IMAGE_NAME}" .

# ===== 6. Create/refresh Docker image backup ========================
echo "Creating Docker image backup..."

# Ensure backup directory exists
sudo mkdir -p "${BACKUP_DIR}"

# Datestamped backup
DATE_STAMP="$(date +"${IMAGE_BACKUP_DATEFMT}")"
BACKUP_FILE_DATED="${BACKUP_DIR}/${IMAGE_NAME}-${DATE_STAMP}.tar"
BACKUP_FILE_LATEST="${BACKUP_DIR}/${IMAGE_BACKUP_NAME}"

echo " - Saving dated backup to: ${BACKUP_FILE_DATED}"
sudo docker save "${IMAGE_NAME}" -o "${BACKUP_FILE_DATED}"

echo " - Updating latest backup symlink/file: ${BACKUP_FILE_LATEST}"
sudo cp "${BACKUP_FILE_DATED}" "${BACKUP_FILE_LATEST}"

echo "Image backup complete."
echo "You can later transfer and load it on another device with:"
echo "  docker load -i ${IMAGE_BACKUP_NAME}"
echo

# ===== 7. Create WeeWX container if it doesn't exist ===============
if docker ps -a --format '{{.Names}}' | grep -qx "${CONTAINER_NAME}"; then
  echo "Container '${CONTAINER_NAME}' already exists. Skipping creation."
else
  echo "Creating WeeWX container '${CONTAINER_NAME}'..."

  # NOTE:
  #  - --privileged is recommended in the original project for USB/SDR access
  #  - Port 80 is exposed for the embedded nginx server
  #  - TZ is set; change TZ_DEFAULT above if you want a different default
  docker run -d \
    --name "${CONTAINER_NAME}" \
    --privileged \
    --restart unless-stopped \
    -p "${HTTP_PORT}:80" \
    -e TZ="${TZ_DEFAULT}" \
    -v "$PWD/config":"/home/weewx/config" \
    "${IMAGE_NAME}"
fi

# ===== 8. Install health-check script ===============================
echo "Installing health-check script to /usr/local/bin/weewx-healthcheck.sh ..."
sudo tee /usr/local/bin/weewx-healthcheck.sh >/dev/null << 'EOF'
#!/bin/bash
set -euo pipefail

CONTAINER_NAME="weewx"

# Check if container exists
if ! docker ps -a --format '{{.Names}}' | grep -qx "${CONTAINER_NAME}"; then
  logger -t weewx-healthcheck "Container '${CONTAINER_NAME}' does not exist. Nothing to do."
  exit 0
fi

# Check if container is running
if docker ps --format '{{.Names}}' | grep -qx "${CONTAINER_NAME}"; then
  # All good
  exit 0
fi

logger -t weewx-healthcheck "Container '${CONTAINER_NAME}' is not running. Attempting to start..."
if docker start "${CONTAINER_NAME}" >/dev/null 2>&1; then
  logger -t weewx-healthcheck "Successfully started container '${CONTAINER_NAME}'."
else
  logger -t weewx-healthcheck "Failed to start container '${CONTAINER_NAME}'."
fi
EOF

sudo chmod +x /usr/local/bin/weewx-healthcheck.sh

# ===== 9. Install cron-based health check ==========================
echo "Installing cron job for WeeWX health check (every 5 minutes)..."
CRON_FILE="/etc/cron.d/weewx-healthcheck"
sudo tee "${CRON_FILE}" >/dev/null << 'EOF'
*/5 * * * * root /usr/local/bin/weewx-healthcheck.sh
EOF
sudo chmod 644 "${CRON_FILE}"

# ===== 10. Install systemd service for autostart ===================
echo "Installing systemd service /etc/systemd/system/weewx-docker.service ..."
sudo tee /etc/systemd/system/weewx-docker.service >/dev/null << 'EOF'
[Unit]
Description=WeeWX Docker container
Requires=docker.service
After=docker.service

[Service]
Restart=always
RestartSec=10

ExecStart=/usr/bin/docker start -a weewx
ExecStop=/usr/bin/docker stop weewx

[Install]
WantedBy=multi-user.target
EOF

echo "Reloading systemd daemon and enabling WeeWX service..."
sudo systemctl daemon-reload
sudo systemctl enable weewx-docker.service

# Start once now (in case it isn't already)
sudo systemctl start weewx-docker.service || true

echo
echo "==============================================================="
echo "WeeWX Docker installation finished."
echo
echo "Web UI:"
echo "  -> http://<IP-of-your-Pi>:${HTTP_PORT}/"
echo
echo "Data & config on host:"
echo "  -> $(pwd)/config"
echo
echo "Docker image backups:"
echo "  -> Dated: ${BACKUP_DIR}/${IMAGE_NAME}-<DATE>.tar"
echo "  -> Latest: ${BACKUP_DIR}/${IMAGE_BACKUP_NAME}"
echo
echo "To restore the image on another system:"
echo "  1) Copy ${IMAGE_BACKUP_NAME} to the new system."
echo "  2) Run: docker load -i ${IMAGE_BACKUP_NAME}"
echo "  3) Recreate the container with a 'docker run' similar to the one used here."
echo
echo "Systemd service:"
echo "  -> sudo systemctl status weewx-docker"
echo
echo "Health check:"
echo "  -> cron runs /usr/local/bin/weewx-healthcheck.sh every 5 minutes."
echo "     Logs are in syslog tagged as 'weewx-healthcheck'."
echo
echo "Remember: '${TARGET_USER}' may need to log out and log back in"
echo "for Docker group membership to take effect."
echo "==============================================================="
