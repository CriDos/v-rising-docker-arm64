# V Rising Dedicated Server on Docker ARM64 (CriDos Fork)

Run the V Rising Dedicated Server inside a Docker container on ARM64 architectures (like Raspberry Pi 4/5, Apple Silicon Macs via Docker Desktop, various ARM cloud instances).

This image uses **Box86/Box64** and **Wine** to emulate and run the necessary x86/x64 Windows components (SteamCMD and the V Rising server itself) on an ARM64 host.

**Note:** This is a fork of [joaop221/v-rising-docker-arm64](https://github.com/joaop221/v-rising-docker-arm64).

## Prerequisites

*   **ARM64 Host System:** Recommended for optimal performance. Running on x86_64 via QEMU is possible during build but very slow for the actual server.
*   **Docker:** Install Docker Engine or Docker Desktop. [Install Docker Engine](https://docs.docker.com/engine/install/)
*   **Git:** Required to clone this repository.

## Building the Image Locally (Recommended for ARM64 Hosts)

You need to clone this repository first because the build process requires files from the `rootfs` directory (like startup scripts).

1.  **Clone the Repository:**
    ```bash
    git clone https://github.com/CriDos/v-rising-docker-arm64.git
    cd v-rising-docker-arm64
    ```

2.  **Build the Docker Image:**
    Execute this command from the repository's root directory (where the `debian.Dockerfile` and `rootfs` folder are located).
    ```bash
    # Tag the image as 'vrising-server-arm64:local'
    docker build -t vrising-server-arm64:local -f debian.Dockerfile .
    ```
    *(This build can take a significant amount of time as it compiles Box86/Box64).*

    *Optional: Building on non-ARM64 Hosts (Cross-Compilation)*
    If you *must* build on an x86_64 host for an ARM64 target, you'll need `buildx` with multi-platform support configured:
    ```bash
    # Make sure buildx is set up: https://docs.docker.com/build/building/multi-platform/
    docker buildx build --platform linux/arm64 -t vrising-server-arm64:local -f debian.Dockerfile . --load
    ```
    *(Note: `--load` makes the image available in your local Docker images list).*

## Running the Container (Using Locally Built Image)

1.  **Create Host Directories for Server Data:**
    The container uses volumes to persist server files and save data outside the container. Create directories on your host machine:
    ```bash
    # Example using home directory:
    mkdir -p ~/vrising-server/data
    mkdir -p ~/vrising-server/server
    ```

2.  **Set Correct Permissions:**
    The container runs processes as user `steam` with UID `1001` and GID `1001`. You need to ensure these directories are writable by this user/group.
    ```bash
    # Set ownership to UID 1001 and GID 1001
    sudo chown -R 1001:1001 ~/vrising-server/data ~/vrising-server/server
    ```
    *(If your host user already has UID/GID 1001, `sudo` might not be strictly necessary, but it's safer to set it explicitly).*

3.  **Run the Container:**
    Use the image tag you defined during the build (`vrising-server-arm64:local`). **Crucially, configure your server using environment variables (`-e`).**
    ```bash
    docker run -d \
        --name vrising-server \
        -p 9876:9876/udp \
        -p 9877:9877/udp \
        -v ~/vrising-server/server:/vrising/server \
        -v ~/vrising-server/data:/vrising/data \
        --restart unless-stopped \
        # --- Essential Server Configuration ---
        -e SERVER_NAME="My ARM V Rising Server" \
        -e WORLD_NAME="MyWorld" \
        -e PASSWORD="A_Very_Secret_Password" \
        # --- Optional Common Settings (See init-server.sh & official docs) ---
        # -e MAX_PLAYERS=40
        # -e ADMIN_STEAM_IDS="STEAMID1,STEAMID2" # Comma-separated Steam64 IDs
        # -e SAVE_INTERVAL_SECONDS=600 # How often to save world (default 600)
        # -e AUTO_UPDATE_ON_START="true" # Attempt update check on start
        # --- End Configuration ---
        vrising-server-arm64:local
    ```

    *   `-d`: Run in detached mode (background).
    *   `--name vrising-server`: Assign a convenient name to the container.
    *   `-p 9876:9876/udp -p 9877:9877/udp`: Map the default game and query ports. Ensure these ports are open on your host/firewall if needed.
    *   `-v ...`: Map the host directories created earlier to the container volumes.
    *   `--restart unless-stopped`: Automatically restart the container unless manually stopped.
    *   `-e KEY="VALUE"`: Set environment variables to configure the server. **Check `rootfs/home/steam/init-server.sh` in this repository for available variables.** You *must* at least set `SERVER_NAME`, `WORLD_NAME`, and `PASSWORD`.

4.  **First Run & Monitoring:**
    *   The *first time* you start the container, it will use SteamCMD (via Box86) to download the V Rising Dedicated Server files (~2-4 GB). This will take time.
    *   Monitor the progress and check for errors:
        ```bash
        docker logs -f vrising-server
        ```
        (Press `Ctrl+C` to stop following logs).
    *   Once the server is running, you should see log messages related to game startup.

## Container Management

*   **View Logs:** `docker logs vrising-server` (add `-f` to follow)
*   **Stop:** `docker stop vrising-server`
*   **Start:** `docker start vrising-server`
*   **Restart:** `docker restart vrising-server`
*   **Remove Container (Stop first):** `docker rm vrising-server` (Your data in `~/vrising-server` will remain)
*   **Remove Local Image:** `docker rmi vrising-server-arm64:local`

## Configuration

Server settings (name, password, game settings, etc.) are primarily controlled via **environment variables** passed to the `docker run` command using the `-e` flag.

*   Consult the `rootfs/home/steam/init-server.sh` script within this repository to see exactly which environment variables are recognized and how they map to the server's configuration files.
*   For details on the meaning of various V Rising server settings, refer to the official documentation: [V Rising Dedicated Server Instructions](https://github.com/StunlockStudios/vrising-dedicated-server-instructions). The container typically modifies `ServerHostSettings.json` and `ServerGameSettings.json` based on the provided environment variables.

## Technical Notes

*   **SteamCMD Emulation:** [SteamCMD](https://developer.valvesoftware.com/wiki/SteamCMD) (i386) is required to download/update the server. This is run via [Box86](https://github.com/ptitSeb/box86) emulation.
*   **V Rising Server Execution:** The V Rising server executable is a Windows x64 application. It is run using a combination of [Box64](https://github.com/ptitSeb/box64) and [Wine (64-bit)](https://www.winehq.org/). See: [Box64 + Wine Notes](https://github.com/ptitSeb/box64?tab=readme-ov-file#notes-about-wine).

## Credits and Links

This image was based on implementations and documentation available at:

*   **Original Repository:** [joaop221/v-rising-docker-arm64](https://github.com/joaop221/v-rising-docker-arm64)
*   [Official V Rising Dedicated Server Instructions](https://github.com/StunlockStudios/vrising-dedicated-server-instructions)
*   [TrueOsiris/docker-vrising](https://github.com/TrueOsiris/docker-vrising) (x86_64 reference)
*   [gogoout/vrising-arm64](https://github.com/gogoout/vrising-server-arm64) (Previous ARM64 effort)
*   [Box86 by ptitSeb](https://github.com/ptitSeb/box86)
*   [Box64 by ptitSeb](https://github.com/ptitSeb/box64)