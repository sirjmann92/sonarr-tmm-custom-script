#!/bin/bash

# tinyMediaManager HTTP API information: https://www.tinymediamanager.org/docs/http-api
    # NOTE: tMM's HTTP API documentation indicates the first library index is 0.
    # However, during the building of this script I discovered that it actually starts at 1, at least for the tvshow module
# Sonarr (partial) Custom Script documentation with some Sonarr environment variables: https://wiki.servarr.com/sonarr/custom-scripts

# User-defined variables
queue_file="/config/logs/tmm_update_queue" # I use the Sonarr log directory, you can move this if you prefer
lock_file="/config/logs/tmm_update_lock" # I use the Sonarr log directory, you can move this if you prefer
log_file="/config/logs/tmm_update.log" # I use the Sonarr log directory, you can move this if you prefer
tmm_log_file="/tmm-logs/tmm.log" # tMM log directory - Sonarr must have read access
api_key="redacted" # tMM API key
api_url="http://redacted:redacted/api/tvshow" # tMM server URL and API module (tvshow/movies)
max_log_size=1048576 # Maximum log size before rotating
delay=20 # Delay to check tmm.log for changes
series_delete_delay=3 # Small delay to confirm series deletion
retry_count=10 # Number of times to retry, used in SeriesDelete command
declare -A library_paths=( # Add as many tMM data sources as you need, in the order they are listed in tMM
    [1]="/share/Shows"
    [2]="/share/Anime/Shows"
#    [3]="/another/tmm/data/source"
#    [4]="/yet/another/tmm/data/source"
)

# Sonarr environment variables
event="${sonarr_eventtype}"
series_path="${sonarr_series_path}"
series_title="${sonarr_series_title}"
series_deletedfiles="${sonarr_series_deletedfiles}"
relative_path="${sonarr_episodefile_relativepath:-$sonarr_episodefile_relativepaths}"
previous_relative_path="${sonarr_episodefile_previousrelativepath:-$sonarr_episodefile_previousrelativepaths}"
episode_path="${sonarr_episodefile_path:-$sonarr_episodefile_paths}"
previous_paths="${sonarr_episodefile_previouspath:-$sonarr_episodefile_previouspaths}"

# tMM commands
update_show='{"action":"update", "scope":{"name":"show", "args":["'"${series_path}"'"]}}'
update_all='{"action":"update", "scope":{"name":"all"}}'
scrape_new='{"action":"scrape", "scope":{"name":"new"}}'
scrape_unscraped='{"action":"scrape", "scope":{"name":"unscraped"}}'
scrape_all='{"action":"scrape", "scope":{"name":"all"}}'

# tvshow.nfo file location
nfo_file="${series_path}/tvshow.nfo"

# Log rotation function
if [ -f "$log_file" ] && [ "$(stat -c%s "$log_file")" -ge "$max_log_size" ]; then
    [ -f "$log_file.old" ] && rm "$log_file.old"
    mv "$log_file" "$log_file.old"
    > "$log_file"
fi

# Function to log messages with timestamp and log level
log() {
    local level=$1
    local message=$2
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $message" >> "$log_file"
}

# Function to create a lock file
create_lock() {
    exec 200>"$lock_file"
    flock -n 200 && return 0 || return 1
}

# Function to remove a lock file
remove_lock() {
    rm -f "$lock_file"
}

# Function to see if tMM is idle, based on tmm.log size
is_tmm_idle() {
    local initial_size=$(stat -c%s "$tmm_log_file")
    sleep "$delay"
    local new_size=$(stat -c%s "$tmm_log_file")
    if [[ "$initial_size" -eq "$new_size" ]]; then
        log "INFO" "tMM is idle."
        return 0
    else
        log "INFO" "tMM is busy. Initial log size: $initial_size, New log size: $new_size"
        return 1
    fi
}

# Function to process commands from the queue file
process_queue() {
    while [ -s "$queue_file" ]; do
        local delay_cycles=0
        while ! is_tmm_idle; do
            delay_cycles=$((delay_cycles + 1))
            log "INFO" "Waiting for tMM to become idle. Delay cycle: $delay_cycles"
        done
        
        local command=$(head -n 1 "$queue_file")
        sed -i '1d' "$queue_file"
        
        run_curl_command "$command"
    done
    log "INFO" "Queue is empty, ending script."
    remove_lock
}

# Function to wrap commands in brackets for JSON formatting
wrap() {
    echo "[$1]"
}

# Function to construct and execute curl commands
run_curl_command() {
    local command=$1
    if [ -n "$command" ]; then
        log "INFO" "Executing command(s) from queue: curl -d \"$command\" -H \"Content-Type: application/json\" -H \"api-key: $api_key\" -X POST $api_url"
        response=$(curl -s -d "$command" -H "Content-Type: application/json" -H "api-key: $api_key" -X POST "$api_url")
        log "INFO" "Response from tMM: $response"
    else
        log "WARN" "No command(s) provided."
    fi
}

# Function to add tMM commands to a queue file
add_to_queue() {
    local command=$1
    {
        flock -x 200
        echo "$(wrap "$command")" >> "$queue_file"
        log "INFO" "Added command(s) to queue: $(wrap "$command")"
    } 200>"$queue_file.lock"
}

# Flag for unsupported events
unsupported_event=false

# Function to queue tMM commands based on Sonarr event type
queue_commands() {
    case "$event" in
    "SeriesDelete") # Sonarr delete show helper
        if [ "$series_deletedfiles" == "True" ]; then
            log "INFO" "Deleting series directory: ${series_path}"
            rm -rf "$series_path"
            attempt=0

            while [ -d "$series_path" ] && [ $attempt -lt $retry_count ]; do
                log "WARN" "Waiting for directory to be deleted..."
                sleep "$series_delete_delay"
                attempt=$((attempt + 1))
            done

            if [ -d "$series_path" ]; then
                log "ERROR" "Directory ${series_path} could not be deleted. Exiting."
                return
            else
                log "INFO" "Directory ${series_path} successfully deleted."
            fi
        fi

        log "INFO" "Removing ${series_title} from the tMM library."
        add_to_queue "$update_show"
        ;;
    "EpisodeFileDelete") # When an episode is deleted, update the show in tMM to remove it from the library
        log "INFO" "Episode file deleted: ${relative_path}."
        log "INFO" "Updating ${series_title}."
        add_to_queue "$update_show"
        ;;
    "Rename") # On file rename, update the library/show and scrape renamed items (renamed files are detected as new files in tMM)
        log "INFO" "Previous path(s): ${previous_relative_path}"
        log "INFO" "New path(s): ${relative_path}"
        if [ -f "$nfo_file" ]; then
            log "INFO" "${series_title} already exists in tMM."
            log "INFO" "Updating ${series_title} and scraping renamed items."
            add_to_queue "$update_show,$scrape_new"
            add_to_queue "$scrape_unscraped" # Catch and scrape any previously missed items
        else
            log "INFO" "${series_title} does not exist in tMM."
            # If the show doesn't exist in tMM, update the library by index to pick up renamed items and scrape them
            library_found=false
            for library_index in "${!library_paths[@]}"; do
                if [[ "$series_path" == ${library_paths[$library_index]}* ]]; then
                    log "INFO" "Updating library index $library_index and scraping renamed items."
                    update_library='{"action":"update", "scope":{"name":"single", "args":["'"${library_index}"'"]}}'
                    add_to_queue "$update_library,$scrape_new"
                    add_to_queue "$scrape_unscraped" # Catch and scrape any previously missed items
                    library_found=true
                    break
                fi
            done
            # If library path is incorrect or not found, update all libraries and scrape new and unscraped items (fallback)
            if [ "$library_found" = false ]; then
                log "WARN" "Path not found. Updating all libraries and scraping new and unscraped items."
                add_to_queue "$update_all,$scrape_new"
                add_to_queue "$scrape_unscraped" # Catch and scrape any previously missed items
            fi
        fi
        ;;
    "Download") # If the show exists in tMM, update the show and scrape new items
        if [ -f "$nfo_file" ]; then
            log "INFO" "Episode file: ${relative_path}"
            log "INFO" "${series_title} already exists in tMM."
            log "INFO" "Updating ${series_title} and scraping new items."
            add_to_queue "$update_show,$scrape_new"
            add_to_queue "$scrape_unscraped" # Catch and scrape any previously missed items
        else
            log "INFO" "${series_title} does not exist in tMM."
            # If the show doesn't exist in tMM, update only the library by index to pick up the new show and scrape new items
            library_found=false
            for library_index in "${!library_paths[@]}"; do
                if [[ "$series_path" == ${library_paths[$library_index]}* ]]; then
                    log "INFO" "Updating library index $library_index and scraping new items."
                    update_library='{"action":"update", "scope":{"name":"single", "args":["'"${library_index}"'"]}}'
                    add_to_queue "$update_library,$scrape_new"
                    add_to_queue "$scrape_unscraped" # Catch and scrape any previously missed items
                    library_found=true
                    break
                fi
            done
            # If library path is incorrect or not found, update all libraries and scrape new and unscraped items (fallback)
            if [ "$library_found" = false ]; then
                log "WARN" "Path not found. Updating all libraries and scraping new and unscraped items."
                add_to_queue "$update_all,$scrape_new"
                add_to_queue "$scrape_unscraped" # Catch and scrape any previously missed items
            fi
        fi
        ;;
    *) # Catch-all for unsupported events
        log "INFO" "Unsupported event type: ${event}. No action taken..."
        unsupported_event=true
        ;;
    esac
}

# Main script logic
{
    # Begin logging
    log "INFO" "Event type: ${event}"
    [ -n "$series_title" ] && log "INFO" "Series title: ${series_title}"
    [ -n "$series_path" ] && log "INFO" "Series path: ${series_path}"

    if create_lock; then
        queue_commands
        if [ "$unsupported_event" = false ]; then
            log "INFO" "Checking if tMM is idle..."
            process_queue
        fi
    else
        if [ "$unsupported_event" = false ]; then
            log "WARN" "Another instance is running. Adding command(s) to queue and exiting."
            queue_commands
        fi
    fi

} 2>&1 | tee -a "$log_file"
