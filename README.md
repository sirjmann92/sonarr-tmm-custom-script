Kitchen Sink Script for Sonarr and tinyMediaManager
===================================================

Disclaimer
----------

I am *NOT* a developer. I'm just a guy trying to improve more tedious aspects of day-to-day life and sharing what I've created. I leaned heavily on AI to help produce my concepts and then tested for my use case and made adjustments. The script is not perfect but it works pretty well in my environment from my testing. YMMV.

Feel free to use this and let me know your results, problems, or improvements that could be made.

Introduction
------------

I prefer to use tinyMediaManager (tMM) to manage my media metadata because it provides more flexibility than Sonarr's basic metadata system, which exclusively pulls from TheTVDB. Nothing wrong with this for many people, but I find that sometimes things are missing from one metadata source that you can find at another (e.g., cast/actors might be missing from TheTVDB but can be found by scraping with TMDB or IMDB).

tMM has an HTTP API that allows you to send commands to a running instance of the application. This is ideal for self-hosted setups where Sonarr and/or tMM are running as services or in containers. The tMM HTTP API has endpoints for updating and scraping, as well as some other things (some of which were added based on my personal requests).

For a long time, I was using the basic tMM HTTP API scripts that everyone around the web is probably using:
```sh
curl -d '[{"action":"update", "scope":{"name":"all"}},{"action":"scrape", "scope":{"name":"new"}}]' -H "Content-Type: application/json" -H "api-key: redacted" -X POST http://redacted:redacted/api/tvshow
```

This mostly works, but there are some issues that bothered me and caused me to have to do a lot of manual work for something I was attempting to automate.

Issues Addressed
----------------

1.  **Inefficiency**: It's not always necessary (or desired) to update all libraries, or even a library index, when it would suffice to update just the show in tMM.
2.  **Queue Management**: tMM's queue system is a bit wonky; updates may execute while another action is being processed, causing things to get missed.
3.  **Conditional Logic**: Reduce the need for multiple custom scripts in Sonarr for different events

Approach
--------

I started out thinking I could create a script to check if a show exists in tMM when sending commands from Sonarr, but tMM's HTTP API options are limited. Ultimately, I ended up checking for the existence of the `tvshow.nfo` file. If it doesn't exist, tMM hasn't scraped the show yet, so the script should update the library and scrape new items. After the first episode, only the "show" needs to be updated in tMM, which is much more efficient.

Summary
-------

This script automates the interaction between Sonarr and tinyMediaManager (tMM). It handles various Sonarr events related to TV shows and episodes and ensures that tMM updates its database accordingly. The script manages a queue of commands for tMM, checks if tMM is idle (based on `tmm.log` file size) before executing these commands, and logs all activities.

Features
--------

### Initialization and Logging

-   User-configurable variables (e.g., file paths, tMM API details, log rotation size).
-   Rotates the log file when it reaches a certain size to prevent it from becoming too large.
-   Logs script execution details, including the Sonarr event type and relevant information.

### Lock File Management

-   Creates a lock file to prevent multiple instances of the script from running simultaneously.
-   Removes the lock file upon script completion.

### Idle Check for tMM

-   Checks if tMM is idle based on the size of its log file to ensure commands are only sent when tMM is not busy.
-   The script checks every 20 seconds for `tmm.log` file size changes. This may need adjustment based on your system.

### Command Queue Management

-   Adds commands to a queue file and processes the queue.
-   Waits until tMM is idle before executing commands from the queue.

### Handling Sonarr Events

-   Handles different Sonarr events (SeriesDelete, EpisodeFileDelete, Rename, and Download) and queues appropriate tMM commands based on these events.
    -   **SeriesDelete**: Delete the Series directory. tMM update "show" only
        -  Sonarr's ability to delete an entire series is slow, at best, and often fails to remove the directory (posibly because tMM or other external applications have added files). This script will force removal of the directory immediately and confirm it has been deleted before sending any commands to tMM. 
    -   **EpisodeFileDelete**: tMM update "show" only
    -   **Rename**: tMM update "show" and scrape "new"
        - tMM sees renamed files as "New" files, appropriately. So, we need to rediscover and rescrape the files when a Rename event is detected.
    -   **Download**:
        -   If show exists: tMM update "show" and scrape "new"
        -   If not: update "library" and scrape "new"
        -   If unknown: update "all" and scrape both "new" and "unscraped" (fallback)

### Unknown or Unsupported Event Types

-   Logs unsupported or unknown event types and exits without performing any actions.

Prerequisites
-------------

1.  Sonarr and tMM must be installed and working.
2.  tMM configured to use its HTTP API: [tMM HTTP API Documentation](https://www.tinymediamanager.org/docs/http-api).
3.  Sonarr must have access to the tMM log directory (read-only at minimum).
4.  If using Docker for Sonarr, add a volume mapping to your Compose/Run config (e.g., `/path/to/tmm/logs:/tmm-logs:ro`).
5.  Sonarr must not be allowed to create `tvshow.nfo` (Metadata settings).
6.  The script must be executable:
    `chmod +x /path/to/kitchen_sink.sh`
7. Patience - The script checks the `tmm.log` file to determine if tMM is idle before sending any commands. Don't assume you're going to see activity in tMM immediately when events occur in Sonarr. The script will continually add commands to, and pull commands from, the queue file, and then send them to tMM when it's ready. Adjust the `$delay` variable if you notice overlapping commands in tMM.

Instructions
------------

1. **Download kitchen-sink.sh from the repository**
2.  **Update the User-defined variables and save the script**
3.  **Make the script executable**:
    - `chmod +x /path/to/kitchen_sink.sh`
1.  **Open Sonarr web interface**
2.  **Navigate to Connect settings**:
    -   Click on Settings in the left-hand menu.
    -   Click on the Connect tab.
3.  **Add a new Custom Script**:
    -   Click the + button to add a new notification.
    -   Select Custom Script from the list of available options.
4.  **Configure the Custom Script**:
    -   **Name**: Give your script a name for easy identification (e.g. tMM - Kitchen Sink)
    -   **Path**: Enter the full path to your script file (e.g., /path/to/kitchen_sink.sh).
5.  **Select the events you want the script to trigger on**:
    -   **Recommended**:
        -  On Import Complete
        -  On Rename, On Series Delete
        -  On Episode File Delete
        -  On Episode File Delete for Upgrade
    -   **Tags**: Optionally, add tags if you want the script to run only for series with specific tags.
6.  **Click the Save button**
7.  **Navigate to Metadata settings**
    -  Click on Seeings in the left-hand menu.
    -  Click on the Metadata tab.
8.  **Disable tvshow.nfo creation (if it's enabled)**
    -  Click on Kodi (XBMC) / Emby
    -  Uncheck "Series Metadata (tvshow.nfo with full series metadata)"
9.  **If you have Plex/Jellyfin configured to scrape metadata, you may need/want to disable those as well!**

Example log
-----------

```sh
2024-07-29 14:11:58 [INFO] Event type: Test
2024-07-29 14:11:58 [INFO] Unsupported event type: Test. No action taken...
2024-07-29 14:13:31 [INFO] Event type: EpisodeFileDelete
2024-07-29 14:13:31 [INFO] Series title: Heroes
2024-07-29 14:13:31 [INFO] Series path: /share/Shows/Heroes (2006)
2024-07-29 14:13:31 [INFO] Episode file deleted: Season 01/Heroes - S01E06 - Better Halves.mkv.
2024-07-29 14:13:31 [INFO] Updating Heroes.
2024-07-29 14:13:31 [INFO] Added command(s) to queue: [{"action":"update", "scope":{"name":"show", "args":["/share/Shows/Heroes (2006)"]}}]
2024-07-29 14:13:31 [INFO] Checking if tMM is idle...
2024-07-29 14:13:51 [INFO] tMM is idle.
2024-07-29 14:13:51 [INFO] Executing command(s) from queue: curl -d "[{"action":"update", "scope":{"name":"show", "args":["/share/Shows/Heroes (2006)"]}}]" -H "Content-Type: application/json" -H "api-key: redacted" -X POST http://redacted:redacted/api/tvshow
2024-07-29 14:13:51 [INFO] Response from tMM: {"message":"commands prepared"}
2024-07-29 14:13:51 [INFO] Queue is empty, ending script.
2024-07-29 14:14:35 [INFO] Event type: Download
2024-07-29 14:14:35 [INFO] Series title: Heroes
2024-07-29 14:14:35 [INFO] Series path: /share/Shows/Heroes (2006)
2024-07-29 14:14:35 [INFO] Episode file: Season 01/Heroes - S01E06 - Better Halves.mkv
2024-07-29 14:14:35 [INFO] Heroes already exists in tMM.
2024-07-29 14:14:35 [INFO] Updating Heroes and scraping new items.
2024-07-29 14:14:35 [INFO] Added command(s) to queue: [{"action":"update", "scope":{"name":"show", "args":["/share/Shows/Heroes (2006)"]}},{"action":"scrape", "scope":{"name":"new"}}]
2024-07-29 14:14:35 [INFO] Checking if tMM is idle...
2024-07-29 14:14:55 [INFO] tMM is idle.
2024-07-29 14:14:55 [INFO] Executing command(s) from queue: curl -d "[{"action":"update", "scope":{"name":"show", "args":["/share/Shows/Heroes (2006)"]}},{"action":"scrape", "scope":{"name":"new"}}]" -H "Content-Type: application/json" -H "api-key: redacted" -X POST http://redacted:redacted/api/tvshow
2024-07-29 14:14:55 [INFO] Response from tMM: {"message":"commands prepared"}
2024-07-29 14:14:55 [INFO] Queue is empty, ending script.
2024-07-29 14:18:01 [INFO] Event type: EpisodeFileDelete
2024-07-29 14:18:01 [INFO] Series title: Heroes
2024-07-29 14:18:01 [INFO] Series path: /share/Shows/Heroes (2006)
2024-07-29 14:18:01 [INFO] Episode file deleted: Season 01/Heroes - S01E07 - Nothing to Hide.mkv.
2024-07-29 14:18:01 [INFO] Updating Heroes.
2024-07-29 14:18:01 [INFO] Added command(s) to queue: [{"action":"update", "scope":{"name":"show", "args":["/share/Shows/Heroes (2006)"]}}]
2024-07-29 14:18:01 [INFO] Checking if tMM is idle...
2024-07-29 14:18:21 [INFO] tMM is busy. Initial log size: 937864, New log size: 955992
2024-07-29 14:18:21 [INFO] Waiting for tMM to become idle. Delay cycle: 1
2024-07-29 14:18:41 [INFO] tMM is busy. Initial log size: 955992, New log size: 976833
2024-07-29 14:18:41 [INFO] Waiting for tMM to become idle. Delay cycle: 2
2024-07-29 14:19:01 [INFO] tMM is busy. Initial log size: 976833, New log size: 997672
2024-07-29 14:19:01 [INFO] Waiting for tMM to become idle. Delay cycle: 3
2024-07-29 14:19:21 [INFO] tMM is busy. Initial log size: 997672, New log size: 1014399
2024-07-29 14:19:21 [INFO] Waiting for tMM to become idle. Delay cycle: 4
2024-07-29 14:19:41 [INFO] tMM is busy. Initial log size: 1014399, New log size: 1035236
2024-07-29 14:19:41 [INFO] Waiting for tMM to become idle. Delay cycle: 5
2024-07-29 14:20:01 [INFO] tMM is busy. Initial log size: 1035236, New log size: 1054500
2024-07-29 14:20:01 [INFO] Waiting for tMM to become idle. Delay cycle: 6
2024-07-29 14:20:21 [INFO] tMM is busy. Initial log size: 1054500, New log size: 1073709
2024-07-29 14:20:21 [INFO] Waiting for tMM to become idle. Delay cycle: 7
2024-07-29 14:20:41 [INFO] tMM is busy. Initial log size: 1073709, New log size: 1095870
2024-07-29 14:20:41 [INFO] Waiting for tMM to become idle. Delay cycle: 8
2024-07-29 14:21:01 [INFO] tMM is busy. Initial log size: 1095870, New log size: 1111943
2024-07-29 14:21:01 [INFO] Waiting for tMM to become idle. Delay cycle: 9
2024-07-29 14:21:21 [INFO] tMM is idle.
2024-07-29 14:21:21 [INFO] Executing command(s) from queue: curl -d "[{"action":"update", "scope":{"name":"show", "args":["/share/Shows/Heroes (2006)"]}}]" -H "Content-Type: application/json" -H "api-key: redacted" -X POST http://redacted:redacted/api/tvshow
2024-07-29 14:21:21 [INFO] Response from tMM: {"message":"commands prepared"}
2024-07-29 14:21:21 [INFO] Queue is empty, ending script.
2024-07-29 14:22:04 [INFO] Event type: Download
2024-07-29 14:22:04 [INFO] Series title: Heroes
2024-07-29 14:22:04 [INFO] Series path: /share/Shows/Heroes (2006)
2024-07-29 14:22:04 [INFO] Episode file: Season 01/Heroes - S01E07 - Nothing to Hide.mkv
2024-07-29 14:22:04 [INFO] Heroes already exists in tMM.
2024-07-29 14:22:04 [INFO] Updating Heroes and scraping new items.
2024-07-29 14:22:04 [INFO] Added command(s) to queue: [{"action":"update", "scope":{"name":"show", "args":["/share/Shows/Heroes (2006)"]}},{"action":"scrape", "scope":{"name":"new"}}]
2024-07-29 14:22:04 [INFO] Checking if tMM is idle...
2024-07-29 14:22:24 [INFO] tMM is idle.
2024-07-29 14:22:24 [INFO] Executing command(s) from queue: curl -d "[{"action":"update", "scope":{"name":"show", "args":["/share/Shows/Heroes (2006)"]}},{"action":"scrape", "scope":{"name":"new"}}]" -H "Content-Type: application/json" -H "api-key: redacted" -X POST http://redacted:redacted/api/tvshow
2024-07-29 14:22:24 [INFO] Response from tMM: {"message":"commands prepared"}
2024-07-29 14:22:24 [INFO] Queue is empty, ending script.
```
