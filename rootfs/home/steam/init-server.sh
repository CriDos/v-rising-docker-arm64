#!/bin/bash

# Define paths
server=/vrising/server
data=/vrising/data

# Check if running as root (security warning)
if [ $(id -u) -eq 0 ]; then
	echo "WARNING: Running steamcmd or the server as root user is a security risk. See: https://developer.valvesoftware.com/wiki/SteamCMD" >&2
	echo "TIP: This image provides a 'steam' user (UID: $(id -u steam), GID: $(id -g steam)) as default."
fi

# Check if the data directory exists and create it if not
# This is important because we'll write the log file here
mkdir -p "$data"

# Check if we have proper read/write permissions for server and data directories
if [ ! -r "$server" ] || [ ! -w "$server" ]; then
    echo "ERROR: Read/write permissions issue with $server! Please ensure the container user ($(id -u):$(id -g)) has access." >&2
    echo "Hint: On the host, run 'sudo chown -R $(id -u):$(id -g) path/to/your/server/volume'" >&2
    exit 1
fi
if [ ! -r "$data" ] || [ ! -w "$data" ]; then
    echo "ERROR: Read/write permissions issue with $data! Please ensure the container user ($(id -u):$(id -g)) has access." >&2
    echo "Hint: On the host, run 'sudo chown -R $(id -u):$(id -g) path/to/your/data/volume'" >&2
    exit 1
fi

# --- Signal Handling for Graceful Shutdown ---
term_handler() {
	echo "SIGTERM received, shutting down V Rising Server..."

	# Find the VRisingServer.exe process started by wine64
	PID=$(pgrep -of "/usr/local/bin/wine64 $server/VRisingServer.exe")
	if [[ -z $PID ]]; then
		echo "Could not find VRisingServer.exe PID. Assuming server is already stopped or failed to start."
	else
		echo "Sending SIGTERM (15) to V Rising Server PID: $PID"
		kill -n 15 "$PID"
		# Wait for the process to terminate gracefully (with a timeout)
		echo "Waiting for server process to exit..."
		timeout 30 wait "$PID" # Wait up to 30 seconds
		wait_status=$?
		if [ $wait_status -eq 124 ]; then
		    echo "Server did not shut down gracefully within 30s, force killing may be needed (but wineserver -k should handle it)."
		elif [ $wait_status -ne 0 ]; then
		    echo "Server exited with status $wait_status."
		else
		    echo "Server process exited gracefully."
		fi
	fi

    echo "Shutting down wineserver..."
	wineserver -k # Politely ask Wine server to shut down associated processes
	sleep 2 # Give wineserver a moment
	echo "Shutdown complete."
	exit 0 # Exit script cleanly
}

# Trap SIGTERM signal (sent by 'docker stop')
trap 'term_handler' SIGTERM

# --- SteamCMD Update ---
echo " "
echo "[+] Updating SteamCMD files..."
echo " "
export LD_LIBRARY_PATH="/home/steam/linux32:${LD_LIBRARY_PATH}" # Ensure box86 finds libraries
status_steamcmd=1

# Retry loop for steamcmd self-update, sometimes it fails first time
retry_count=0
max_retries=3
while [ $status_steamcmd -ne 0 ] && [ $retry_count -lt $max_retries ]; do
	box86 /home/steam/linux32/steamcmd +quit
	status_steamcmd=$?
    if [ $status_steamcmd -ne 0 ]; then
        retry_count=$((retry_count + 1))
        echo "SteamCMD update failed (Exit Code: $status_steamcmd), retrying (${retry_count}/${max_retries})..."
        sleep 5
    fi
done

if [ $status_steamcmd -ne 0 ]; then
    echo "ERROR: SteamCMD failed to update after $max_retries attempts. Exiting." >&2
    exit 1
fi
echo "[+] SteamCMD update complete."
echo " "

# --- V Rising Server Update/Validation ---
echo "[+] Updating/Validating V-Rising Dedicated Server files..."
echo " "
# Force platform type to windows as we are running the Windows server via Wine
box86 /home/steam/linux32/steamcmd +@sSteamCmdForcePlatformType windows +force_install_dir "$server" +login anonymous +app_update 1829350 validate +quit
update_status=$?
if [ $update_status -ne 0 ]; then
    echo "WARNING: SteamCMD app_update failed (Exit Code: $update_status). Server might be outdated or files corrupted." >&2
    # Decide if you want to exit here or try running anyway
    # exit 1
fi

# Check if download was successful (basic check)
if [ ! -f "$server/VRisingServer.exe" ]; then
    echo "ERROR: VRisingServer.exe not found in $server after update attempt. Exiting." >&2
    exit 1
fi
echo "[+] V Rising Server update/validation process finished."
echo "Installed AppID: $(cat "$server/steam_appid.txt" 2>/dev/null || echo 'Not found')" # Display AppID if file exists
echo " "

# --- Prepare Data Directory ---
mkdir -p "$data/Settings" # Ensure Settings subdirectory exists

# --- Start Xvfb (Virtual Framebuffer) ---
echo "[+] Starting Xvfb (Virtual Display) for Wine..."
# Clean up potential stale lock file
rm -f /tmp/.X0-lock
# Start Xvfb on display :0
Xvfb :0 -screen 0 1024x768x16 &
Xvfb_PID=$!
sleep 2 # Give Xvfb a moment to start
# Basic check if Xvfb started
if ! ps -p $Xvfb_PID > /dev/null; then
    echo "ERROR: Failed to start Xvfb. Exiting." >&2
    exit 1
fi
echo "[+] Xvfb started (PID: $Xvfb_PID)."
echo " "

# --- Launch V Rising Server via Wine ---
echo "[+] Launching V Rising Dedicated Server via Wine..."
echo " "

# Define the log file path within the data volume
logfile="$data/VRisingServer_$(date +%Y%m%d_%H%M%S).log"
echo "[+] Server log file will be: $logfile"

# Run the server using Wine within the virtual display
# Pass persistentDataPath pointing to our data volume
# Pass the logFile path pointing to our data volume
DISPLAY=:0.0 wine64 "$server/VRisingServer.exe" -persistentDataPath "$data" -logFile "$logfile" 2>&1 &
# Get the PID of the wine64 command running the server
ServerPID=$!
echo "[+] V Rising Server process started (PID: $ServerPID)."

# --- Log Tailing and Process Waiting ---
# Wait a moment for the log file to potentially be created by the server
sleep 5

# Tail the log file *from the data directory* to দেখতে docker logs
if [ -f "$logfile" ]; then
    echo "[+] Tailing log file: $logfile"
    tail -n 0 -F "$logfile" & # Use -F to handle log rotation/recreation if it happens
else
    echo "WARNING: Log file $logfile not found after 5 seconds. Tailing might not work immediately."
    # Fallback: just wait for the server process
fi

# Wait for the V Rising Server process to exit
echo "[+] Waiting for V Rising Server (PID: $ServerPID) to exit..."
wait $ServerPID
server_exit_code=$?
echo "[+] V Rising Server process (PID: $ServerPID) exited with code: $server_exit_code"

# --- Cleanup ---
# If the script reaches here (meaning the server stopped *not* via SIGTERM),
# try to clean up Xvfb as well.
echo "[+] Cleaning up Xvfb (PID: $Xvfb_PID)..."
kill $Xvfb_PID
wait $Xvfb_PID 2>/dev/null # Wait for Xvfb to exit, ignore errors if already gone

exit $server_exit_code # Exit the script with the server's exit code