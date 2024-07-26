cat << 'EOF' > /root/monitor_cpu.sh
#!/bin/bash

# Log file
LOG_FILE="/root/monitoring.log"
ERROR_LOG="/root/monitoring_error.log"
WEBHOOK_URL=""

# List of essential services (add any other essential services here)
ESSENTIAL_SERVICES=("sshd")

# Function to log messages
log_message() {
    echo "$(date): $1" >> "$LOG_FILE"
}

log_error() {
    echo "$(date): $1" >> "$ERROR_LOG"
}

# Function to send webhook notification
send_webhook() {
    local message=$1
    local priority=$2
    curl -X POST -H "Content-Type: application/json" -d "{\"message\": \"$message\", \"priority\": $priority}" $WEBHOOK_URL
}

# Ensure SSHD has at least 3% CPU
RESERVE_CPU_FOR_SSH() {
    SSHD_PID=$(pgrep sshd)
    if [[ ! -z "$SSHD_PID" ]]; then
        cpulimit -p $SSHD_PID -l 3 &
    fi
}

# Infinite loop to monitor CPU usage continuously
while true; do
    # Reserve CPU for SSH
    RESERVE_CPU_FOR_SSH

    # Get the list of processes using more than 20% CPU
    PROCESSES=$(ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%cpu | awk '$5 > 20.0 {print}')

    # Check if there are any processes to log
    if [[ ! -z "$PROCESSES" ]]; then
        while IFS= read -r line; do
            PID=$(echo $line | awk '{print $1}')
            CPU=$(echo $line | awk '{print $5}')
            CMD=$(echo $line | awk '{print $3}')

            # Determine the CPU usage indicator and priority
            if (( $(echo "$CPU > 50.0" | bc -l) )); then
                message="⬆️🔴 Process ID: $PID, Command: $CMD, CPU Usage: $CPU%"
                priority=3
            else
                message="⬆️ Process ID: $PID, Command: $CMD, CPU Usage: $CPU%"
                priority=2
            fi
            
            log_message "$message"
            send_webhook "$message" "$priority"

            # Check if the process is essential
            IS_ESSENTIAL=0
            for service in "${ESSENTIAL_SERVICES[@]}"; do
                if [[ "$CMD" == *"$service"* ]]; then
                    IS_ESSENTIAL=1
                    break
                fi
            done

            # Kill the process if it's not essential
            if [[ "$IS_ESSENTIAL" -eq 0 ]]; then
                kill -9 "$PID" 2>>"$ERROR_LOG"
                if [[ $? -ne 0 ]]; then
                    error_message="⚠️ Failed to kill process ID: $PID, Command: $CMD"
                    log_error "$error_message"
                    send_webhook "$error_message" 1
                else
                    killed_message="Killed process ID: $PID, Command: $CMD"
                    log_message "$killed_message"
                    send_webhook "$killed_message" 2
                fi
            fi
        done <<< "$PROCESSES"
    fi

    # Sleep for 10 seconds before checking again
    sleep 10
done
EOF
