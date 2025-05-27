## 🌟 Automated n8n Deployment with FFmpeg, yt-dlp, Puppeteer, Caddy & PostgreSQL! 🚀

Sick of wrestling with manual n8n setups? This script is your magical sidekick, ready to spin up n8n on your Ubuntu server in no time! It’s packed with everything you need: a custom n8n image with FFmpeg, yt-dlp, and Puppeteer, a rock-solid PostgreSQL database, Caddy for automatic SSL, plus daily backups and auto-updates. Let’s get your automation dreams soaring! ✨

---

### 🤩 What This Script Brings to the Party!

Think of this script as your automation fairy godmother. It handles:

-   ⚡️ **n8n Installation (via Docker):** Fires up n8n in a cozy containerized home.
-   🛠️ **Custom n8n Docker Image:** Crafts a special n8n image loaded with:
    -   **FFmpeg:** For all your video and audio wizardry.
    -   **yt-dlp:** Your go-to for snagging YouTube videos like a pro.
    -   **Puppeteer (n8n-nodes-puppeteer included):** For epic web scraping and browser automation.
-   🔒 **Automatic SSL/TLS:** Sets up Caddy as a reverse proxy, securing your n8n with a free Let’s Encrypt SSL certificate (our top pick!) or an internal one for quick tests.
-   🧠 **Smart Swap Setup:** Checks your server’s RAM and adds swap space if needed, keeping things smooth even on low-memory servers.
-   💾 **Daily Workflow & Database Backups:** Saves your workflows, credentials, and PostgreSQL database every day at 2 AM, so your hard work is safe.
-   🔄 **Auto-Updates:** Keeps n8n and yt-dlp (both on the host and in the container) fresh with updates every 12 hours—no effort required!
-   🗄️ **Persistent PostgreSQL Storage:** Uses PostgreSQL for reliable, production-ready data storage, with data safely tucked away in a Docker volume.
-   🗣️ **Super Friendly:** Guides you with clear prompts and cheerful messages.
-   🛡️ **Idempotent Magic:** Run it multiple times without worry—it knows what’s already set up and skips or updates as needed.

### 🚀 Getting Started (It’s a Breeze!)

Ready to unleash your n8n superpower? Here’s what you need to get rolling:

#### ✨ Prerequisites

-   **A Fresh Ubuntu Server:** Running Ubuntu 20.04 or later (22.04 recommended).
-   **Root or Sudo Access:** You’ll need sudo powers to run the script.
-   **Domain/Subdomain:** A domain (e.g., n8n.yourdomain.com) with an A record pointing to your server’s public IP. The script will check this for you!
-   **Open Ports:** Ports 80 (HTTP) and 443 (HTTPS) must be open for Caddy and SSL. For example, with UFW:

    ```bash
    sudo ufw allow 80/tcp
    sudo ufw allow 443/tcp
    sudo ufw enable  # If UFW isn’t active
    ```

-   **Internet Connection:** Your server needs to be online to fetch packages and Docker images.
-   **Disk Space:** At least 10GB free for Docker images, PostgreSQL data, and backups.
-   **RAM:** Minimum 1GB (2GB recommended). The script sets up swap for low-memory systems.

#### 🏃‍♂️ Installation Steps

Let’s get that n8n instance up and running!

1.  **Connect to Your Server:** Fire up your terminal and SSH in:

    ```bash
    ssh your_user@your_server_ip
    ```

2.  **Clone the Repository:** Snag the script from GitHub:

    ```bash
    git clone https://github.com/satriyabajuhitam/auto-n8n-complete-v2.git
    ```

3.  **Navigate to the Directory:**

    ```bash
    cd auto-n8n-complete-v2
    ```

4.  **Make the Script Executable:**

    ```bash
    chmod +x complete-deploy-n8n.sh
    ```

5.  **Run the Script!** Here’s where the magic happens:

    ```bash
    sudo ./complete-deploy-n8n.sh
    ```

    The script will chat with you! It’ll ask for your domain (e.g., n8n.example.com). Enter it and hit Enter. The script checks if the DNS is set correctly.
    Next, it’ll ask if you want Let’s Encrypt SSL:

    -   **Recommended (y):** Choose `y`, enter your email, and Caddy will grab a trusted SSL certificate.
    -   **Testing (n):** Choose `n` for an internal certificate (you’ll get a browser warning—fine for testing).

    You can customize the install directory with `-d /path` or skip Docker setup with `-s` if it’s already installed:

    ```bash
    sudo ./complete-deploy-n8n.sh -d /custom/n8n -s
    ```

6.  **Grab a Coffee:** The script will install Docker, build the custom n8n image, set up PostgreSQL, configure Caddy, and more. It may take a few minutes, and the initial startup could take up to 5 minutes. Hang tight! ☕

### 🎉 What You Get After Installation!

When the script waves its wand, you’ll see a success message. Here’s the lowdown:

-   **Access n8n:** Open your browser and visit: 👉 https://your.domain (e.g., https://n8n.example.com)

    If using an internal SSL certificate, bypass the browser’s privacy warning.

-   **n8n’s Home Base:** All configs, data, and files live in: `/home/n8n` (or your custom directory with `-d`).

-   **PostgreSQL Password:** Stored securely in: `/home/n8n/postgres_password.txt` (guard this with your life!).

-   **Auto-Updates:** n8n and yt-dlp update every 12 hours. Check the log: `/home/n8n/update.log`

-   **Daily Backups:** Workflows, credentials, and PostgreSQL dumps are backed up at 2 AM server time:

    -   **Location:** `/home/n8n/files/backup_full/n8n_backup_YYYYMMDD_HHMMSS.tar.gz`
    -   Keeps the 30 latest backups.
    -   **Log:** `/home/n8n/files/backup_full/backup.log`

-   **YouTube Downloads:** Videos grabbed via yt-dlp land in: `/home/n8n/files/youtube_data/`

-   **Using yt-dlp on Host:** To run yt-dlp from the command line:

    ```bash
    export PATH="$PATH:$HOME/.local/bin:/opt/yt-dlp-venv/bin"
    yt-dlp --version
    ```

### 🛡️ Making Your n8n Production-Ready & Secure!

This script sets you up with a solid foundation, but for a battle-ready production environment, let’s fortify your setup! 💪

#### 1. Boost Security

-   **Strong n8n Credentials:** After logging in, set a unique, strong password for your n8n admin account. No defaults allowed!
-   **Firewall Lockdown:** The script opens ports 80 and 443. Ensure port 5678 (n8n’s internal port) is NOT publicly accessible. Limit SSH (port 22) to trusted IPs if possible:

    ```bash
    sudo ufw allow from your.ip.address to any port 22
    ```

-   **Secure Secrets:** The PostgreSQL password is stored in `postgres_password.txt`. For sensitive data (e.g., API keys), use a `.env` file:

    ```bash
    echo "DB_POSTGRES_PASSWORD=your_secure_password" > /home/n8n/.env
    ```

    Update `docker-compose.yml` to use it:

    ```yaml
    services:
      n8n:
        env_file: .env
    ```

-   **Keep the OS Fresh:** Update your server regularly:

    ```bash
    sudo apt update && sudo apt upgrade -y
    sudo apt autoremove -y
    sudo reboot  # If needed
    ```

#### 2. Ensure Stability

-   **PostgreSQL Power:** This script uses PostgreSQL, which is production-ready! The database is stored in a Docker volume (`postgres_data`) for durability.
-   **Resource Limits:** Prevent containers from hogging resources. Add to `docker-compose.yml`:

    ```yaml
    services:
      n8n:
        deploy:
          resources:
            limits:
              cpus: '2.0'
              memory: 4096M
      postgres:
        deploy:
          resources:
            limits:
              cpus: '0.5'
              memory: 512M
      caddy:
        deploy:
          resources:
            limits:
              cpus: '0.5'
              memory: 256M
    ```

    Adjust based on your server specs.
-   **Monitoring:** Keep tabs on your setup:
    -   Check n8n’s health: `curl https://your.domain/healthz`
    -   Monitor resources: `free -h`, `df -h`
    -   Use tools like UptimeRobot or Prometheus/Grafana for alerts.

-   **Off-Site Backups:** Copy backups to cloud storage (e.g., AWS S3, Google Cloud):

    ```bash
    scp /home/n8n/files/backup_full/*.tar.gz user@remote:/path
    ```

    Test restores regularly!

#### 3. Performance Tweaks

-   **Server Resources:** Heavy workflows or Puppeteer may need more RAM/CPU. Upgrade your server if you hit slowdowns.
-   **Timezone Check:** The script sets `GENERIC_TIMEZONE=Asia/Jakarta`. Edit `docker-compose.yml` if you’re in a different region.

#### 4. Log Management

-   **Rotate Logs:** Ensure host logs (`/var/log/syslog`, Docker logs) are rotated to avoid disk issues. Check logrotate configs.
-   **Centralized Logging:** For big setups, send logs to a system like Loki or ELK.

#### 5. Documentation

-   **Record Your Setup:** Note your domain, SSL choice, and backup process. It’ll save you later!

### 🛠️ Troubleshooting Tips

Hit a snag? No worries, we’ve got you covered!

#### n8n Not Loading?

-   Check container status:

    ```bash
    cd /home/n8n
    docker compose ps
    ```

    All containers (n8n, postgres, caddy) should be “Up”. postgres should show (healthy).
-   View logs:

    ```bash
    docker compose logs --tail=50 n8n
    docker compose logs --tail=50 postgres
    docker compose logs --tail=50 caddy
    ```

-   Verify DNS: `dig +short your.domain`
-   Check ports: `sudo netstat -tuln | grep -E ':80|:443'`

#### PostgreSQL Issues?

-   Test connection:

    ```bash
    docker exec -it n8n-postgres-1 psql -U n8n -d n8n -c "SELECT 1;"
    ```

-   Check password: `cat /home/n8n/postgres_password.txt`

#### SSL Problems?

-   Inspect Caddy logs: `docker compose logs caddy | grep -i cert`
-   Try internal TLS for testing:

    ```bash
    sed -i 's/tls .*/tls internal/' /home/n8n/Caddyfile
    docker compose restart caddy
    ```

#### Slow Startup (~5 Minutes)?

-   Normal for the first run due to PostgreSQL setup and image building.
-   If persistent, check resources: `free -h`, `df -h`

### 🙏 Credits & Thanks

Huge shoutout to the open-source heroes behind:

-   n8n
-   Docker & Docker Compose
-   PostgreSQL
-   Caddy
-   Let’s Encrypt
-   FFmpeg
-   yt-dlp
-   Puppeteer

And to the amazing community making automation awesome!

### 📄 License

This project is licensed under the MIT License. See the LICENSE file for details.
Got ideas or run into a hiccup? Open an issue or pull request on the GitHub repository! Let’s make automation epic together! 😊
