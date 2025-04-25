/*
 * server.c - alink_manager: TCP server for drone
 *
 * Compile with:
 *     gcc -pthread -o alink_manager server.c
 *
 * This server listens on port 12355. On startup, it:
 *   - Reads configuration from /etc/wfb.yaml (or /etc/wfb.conf)
 *   - Detects wifi card(s) and SoC type
 *   - Automatically starts alink_drone (via start_alink command)
 *
 * It supports the following commands:
 *   start_alink                    - start alink_drone on the drone.
 *   stop_alink                     - stop alink_drone (killall alink_drone)
 *   restart_majestic               - restart majestic (killall -HUP majestic)
 *   change_channel <channel>       - change channel; waits for confirmation via "confirm_channel_change"
 *   confirm_channel_change         - confirms pending channel change
 *   set_video_mode <size> <fps> <exposure> '<crop>'
 *                                 - atomically set video parameters
 *   restart_wfb                    - restart wifibroadcast and request idr.
 *   restart_msposd                 - restart the msposd process using wifibroadcast
 *
 * Use the --verbose flag on the command line to output detailed debug messages.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <pthread.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <time.h>
#include <getopt.h>

#define PORT 12355
#define BUF_SIZE 1024
#define CONFIRM_TIMEOUT 5 // seconds

// Global verbose flag
int verbose = 0;

// Global current settings
int current_channel = 0;
char current_resolution[32] = "1280x720";
int current_fps = 30;

// Structure to hold pending changes that require confirmation.
// Only channel changes require confirmation now.
typedef struct {
    int pending_channel;
    int original_channel;
    int pending_channel_flag;
    time_t pending_channel_time;

    pthread_mutex_t lock;
} pending_changes_t;

pending_changes_t pending;
 
// Initialize pending changes structure
void init_pending_changes() {
    pending.pending_channel_flag = 0;
    pthread_mutex_init(&pending.lock, NULL);
}

// Function to read configuration file
void read_config() {
    FILE *fp = fopen("/etc/wfb.yaml", "r");
    if (!fp)
        fp = fopen("/etc/wfb.conf", "r");
    if (fp) {
        if (verbose) printf("[DEBUG] Reading configuration file...\n");
        char line[128];
        while (fgets(line, sizeof(line), fp)) {
            // Look for a line containing "channel"
            char *ptr = strstr(line, "channel");
            if (ptr) {
                char sep = (strchr(ptr, ':')) ? ':' : '=';
                ptr = strchr(ptr, sep);
                if (ptr) {
                    current_channel = atoi(ptr + 1);
                    if (verbose) printf("[DEBUG] Read channel from config: %d\n", current_channel);
                }
            }
        }
        fclose(fp);
    } else {
        if (verbose) printf("[DEBUG] No config file found; using default channel 1.\n");
        current_channel = 165;
    }
    if (current_channel <= 0) {
        if (verbose) printf("[DEBUG] Invalid channel value (%d); defaulting to channel 1.\n", current_channel);
        current_channel = 165;
    }
}

// Function to simulate hardware detection
void detect_hardware() {
    if (verbose) {
        printf("[DEBUG] Detected wifi cards: wlan0\n");
        printf("[DEBUG] Detected SoC type: ExampleSoC\n");
    }
}

// Function to start alink_drone
void start_alink_drone() {
    system("/usr/bin/alink_drone > /dev/null &");
    if (verbose)
        printf("[DEBUG] alink_drone started.\n");
}

// Full system initialization
void init_system() {
    read_config();
    detect_hardware();
    start_alink_drone();
}

// Helper function to revert channel change
void revert_channel_change(int orig_channel) {
    char syscmd[128];
    snprintf(syscmd, sizeof(syscmd), "iw dev wlan0 set channel %d", orig_channel);
    if (verbose) printf("[DEBUG] Reverting channel using command: %s\n", syscmd);
    system(syscmd);
    current_channel = orig_channel;
    printf("Channel change timed out. Reverted to channel %d.\n", orig_channel);
}

// Background thread to check for pending channel confirmations
void *confirmation_checker(void *arg) {
    while (1) {
        sleep(1);
        time_t now = time(NULL);
        pthread_mutex_lock(&pending.lock);
        if (pending.pending_channel_flag &&
            difftime(now, pending.pending_channel_time) >= CONFIRM_TIMEOUT) {
            if (verbose) printf("[DEBUG] Channel change confirmation timeout. Reverting...\n");
            revert_channel_change(pending.original_channel);
            pending.pending_channel_flag = 0;
        }
        pthread_mutex_unlock(&pending.lock);
    }
    return NULL;
}

/*
 * update_precrop_rc_local_simple() will update /etc/rc.local.
 * If crop equals "nocrop" it deletes any block between a line starting with
 * "#set by alink_manager" and a line containing "echo setprecrop".
 * Otherwise, it removes any existing block and inserts the new block.
 */
void update_precrop_rc_local_simple(const char *crop) {
    char cmd[512];
    snprintf(cmd, sizeof(cmd),
             "sed -i '/^#set by alink_manager/,/echo setprecrop/{/echo setprecrop/{N; s/\\n[[:space:]]*//;};d}' /etc/rc.local");
    if (system(cmd) != 0) {
        fprintf(stderr, "Error removing old precrop blocks.\n");
        return;
    }
    if (strcmp(crop, "nocrop") == 0)
        return;

    snprintf(cmd, sizeof(cmd),
             "sed -i '/^[[:space:]]*exit 0[[:space:]]*$/i\\\n"
             "#set by alink_manager\\\n"
             "sleep 2\\\n"
             "echo setprecrop %s > /proc/mi_modules/mi_vpe/mi_vpe0\\\n"
             "' /etc/rc.local", crop);
    if (system(cmd) != 0) {
        fprintf(stderr, "Error inserting new precrop block.\n");
    }
}

// Process a command from a client and fill the response.
void process_command(const char *cmd, char *response, size_t resp_size) {
    char command[BUF_SIZE];
    strncpy(command, cmd, BUF_SIZE);
    command[strcspn(command, "\r\n")] = 0;  // remove trailing newline

    if (verbose) printf("[DEBUG] Processing command: %s\n", command);

    // start_alink replaces the old "init" command.
    if (strncmp(command, "start_alink", 11) == 0) {
        init_system();
        snprintf(response, resp_size, "alink_drone started.");
    }
    // stop_alink replaces the old "stop" command.
    else if (strncmp(command, "stop_alink", 10) == 0) {
        int ret = system("killall alink_drone");
        snprintf(response, resp_size, ret == 0 ? "alink_drone stopped." : "Error stopping alink_drone.");
    }
    else if (strncmp(command, "restart_majestic", 16) == 0) {
        int ret = system("killall -HUP majestic");
        snprintf(response, resp_size, ret == 0 ? "majestic restarted." : "Error restarting majestic.");
    }
    else if (strncmp(command, "change_channel", 14) == 0) {
        int new_channel;
        if (sscanf(command, "change_channel %d", &new_channel) == 1) {
            char syscmd[128];
            snprintf(syscmd, sizeof(syscmd), "iw dev wlan0 set channel %d", new_channel);
            if (verbose) printf("[DEBUG] Executing: %s\n", syscmd);
            int ret = system(syscmd);
            if (ret == 0) {
                pthread_mutex_lock(&pending.lock);
                pending.original_channel = current_channel;
                pending.pending_channel = new_channel;
                pending.pending_channel_flag = 1;
                pending.pending_channel_time = time(NULL);
                pthread_mutex_unlock(&pending.lock);
                snprintf(response, resp_size, "Channel change executed. Awaiting ground station confirmation.");
            } else {
                snprintf(response, resp_size, "Failed to change channel.");
            }
        } else {
            snprintf(response, resp_size, "Invalid channel command.");
        }
    }
    else if (strncmp(command, "confirm_channel_change", 22) == 0) {
        pthread_mutex_lock(&pending.lock);
        if (pending.pending_channel_flag) {
            current_channel = pending.pending_channel;
            // Persist change to YAML configuration
            {
                char persist_cmd[128];
                snprintf(persist_cmd, sizeof(persist_cmd),
                         "yaml-cli -i /etc/wfb.yaml -s .wireless.channel %d",
                         current_channel);
                if (verbose) printf("[DEBUG] Persisting channel to YAML: %s\n", persist_cmd);
                system(persist_cmd);
            }
            // Also update /etc/wfb.conf if it exists
            if (access("/etc/wfb.conf", F_OK) == 0) {
                char sed_cmd[128];
                snprintf(sed_cmd, sizeof(sed_cmd), "sed -i 's/\\(channel=\\)[0-9][0-9]*/\\1%d/' /etc/wfb.conf", current_channel);
                system(sed_cmd);
            } else {
                fprintf(stderr, "File /etc/wfb.conf does not exist.\n");
            }
            if (verbose)
                printf("[DEBUG] Channel change confirmed. current_channel = %d\n", current_channel);
            pending.pending_channel_flag = 0;
            pthread_mutex_unlock(&pending.lock);
            snprintf(response, resp_size, "Channel change confirmed. Now on channel %d.", current_channel);
        } else {
            pthread_mutex_unlock(&pending.lock);
            snprintf(response, resp_size, "No pending channel change to confirm.");
        }
    }
    else if (strncmp(command, "set_video_mode", 14) == 0) {
        char size[32], crop[128];
        int new_fps, new_exp;
        if (sscanf(command,
                   "set_video_mode %31s %d %d '%127[^']'",
                   size, &new_fps, &new_exp, crop) == 4) {
            char fallback_size[32] = "", fallback_fps[16] = "", fallback_exp[16] = "";
            FILE *p;
            p = popen("cli -g .video0.size", "r");
            if (p && fgets(fallback_size, sizeof(fallback_size), p))
                fallback_size[strcspn(fallback_size, "\r\n")] = 0;
            if (p) pclose(p);
            p = popen("cli -g .video0.fps", "r");
            if (p && fgets(fallback_fps, sizeof(fallback_fps), p))
                fallback_fps[strcspn(fallback_fps, "\r\n")] = 0;
            if (p) pclose(p);
            p = popen("cli -g .isp.exposure", "r");
            if (p && fgets(fallback_exp, sizeof(fallback_exp), p))
                fallback_exp[strcspn(fallback_exp, "\r\n")] = 0;
            if (p) pclose(p);
            if (verbose) {
                printf("[DEBUG] Fallbacks: size=%s fps=%s exp=%s\n",
                       fallback_size, fallback_fps, fallback_exp);
            }
            char cmdline[256];
            snprintf(cmdline, sizeof(cmdline), "cli -s .video0.size %s", size);
            system(cmdline);
            snprintf(cmdline, sizeof(cmdline), "cli -s .video0.fps %d", new_fps);
            system(cmdline);
            snprintf(cmdline, sizeof(cmdline), "cli -s .isp.exposure %d", new_exp);
            system(cmdline);
            system("killall -HUP majestic");
            size_t clen = strlen(crop);
            if (clen >= 2) {
                if ((crop[0] == '\'' && crop[clen-1] == '\'') ||
                    (crop[0] == '"' && crop[clen-1] == '"')) {
                    crop[clen-1] = '\0';
                    memmove(crop, crop+1, clen-1);
                }
            }
            if (strcmp(crop, "nocrop") != 0) {
                pid_t pid = fork();
                if (pid == 0) {
                    sleep(3);
                    char cmd2[256];
                    snprintf(cmd2, sizeof(cmd2),
                             "echo setprecrop %s > /proc/mi_modules/mi_vpe/mi_vpe0", crop);
                    system(cmd2);
                    _exit(0);
                }
                update_precrop_rc_local_simple(crop);
            } else {
                update_precrop_rc_local_simple(crop);
            }
            snprintf(response, resp_size,
                     "Video mode set. Original was size=%s fps=%s exp=%s.",
                     fallback_size[0] ? fallback_size : "?", 
                     fallback_fps[0] ? fallback_fps : "?",
                     fallback_exp[0] ? fallback_exp : "?");
        } else {
            snprintf(response, resp_size,
                     "Invalid set_video_mode command. Format: set_video_mode <size> <fps> <exposure> '<crop>'");
        }
    }
    // New restart_wfb command.
    else if (strncmp(command, "restart_wfb", 11) == 0) {
        int ret = system("sh -c \"wifibroadcast stop && sleep 1 && wifibroadcast start && sleep 2 && curl localhost/request/idr\"");
        snprintf(response, resp_size, ret == 0 ? "wfb restarted successfully." : "Error restarting wfb.");
    }
    // Replace stop_msposd and start_msposd with restart_msposd command.
    else if (strncmp(command, "restart_msposd", 14) == 0) {
        int ret = system("wifibroadcast restart_msposd");
        snprintf(response, resp_size, ret == 0 ? "msposd restarted." : "Error restarting msposd.");
    }
    else {
        snprintf(response, resp_size, "Unknown command.");
    }
}

// Thread function to handle each client connection.
void *client_handler(void *arg) {
    int client_fd = *(int *)arg;
    free(arg);
    char buffer[BUF_SIZE];
    int bytes_read = read(client_fd, buffer, sizeof(buffer) - 1);
    if (bytes_read > 0) {
        buffer[bytes_read] = '\0';
        char response[BUF_SIZE];
        if (verbose) printf("[DEBUG] Received from client: %s\n", buffer);
        process_command(buffer, response, sizeof(response));
        if (verbose) printf("[DEBUG] Sending response: %s\n", response);
        write(client_fd, response, strlen(response));
    }
    close(client_fd);
    pthread_exit(NULL);
}

int main(int argc, char *argv[]) {
    int opt;
    while ((opt = getopt(argc, argv, "v-:")) != -1) {
        if (opt == 'v')
            verbose = 1;
        else if (opt == '-') {
            if (strcmp(optarg, "verbose") == 0)
                verbose = 1;
        }
    }

    if (verbose)
        printf("[DEBUG] Starting alink_manager server in verbose mode.\n");

    int server_fd;
    struct sockaddr_in server_addr;

    // Load channel from wfb.yaml
	read_config();

    init_pending_changes();

    // Start background confirmation checker thread for channel changes.
    pthread_t checker_tid;
    pthread_create(&checker_tid, NULL, confirmation_checker, NULL);

    if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == -1) {
        perror("socket failed");
        exit(EXIT_FAILURE);
    }
    int optval = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &optval, sizeof(optval));

    server_addr.sin_family = AF_INET;
    server_addr.sin_addr.s_addr = INADDR_ANY;
    server_addr.sin_port = htons(PORT);
    if (bind(server_fd, (struct sockaddr *)&server_addr, sizeof(server_addr)) < 0) {
        perror("bind failed");
        close(server_fd);
        exit(EXIT_FAILURE);
    }

    if (listen(server_fd, 10) < 0) {
        perror("listen failed");
        close(server_fd);
        exit(EXIT_FAILURE);
    }
    printf("alink_manager server running on port %d\n", PORT);

    while (1) {
        struct sockaddr_in client_addr;
        socklen_t addr_len = sizeof(client_addr);
        int *client_fd = malloc(sizeof(int));
        if ((*client_fd = accept(server_fd, (struct sockaddr *)&client_addr, &addr_len)) < 0) {
            perror("accept failed");
            free(client_fd);
            continue;
        }
        if (verbose) {
            char client_ip[INET_ADDRSTRLEN];
            inet_ntop(AF_INET, &(client_addr.sin_addr), client_ip, INET_ADDRSTRLEN);
            printf("[DEBUG] Accepted connection from %s:%d\n", client_ip, ntohs(client_addr.sin_port));
        }
        pthread_t tid;
        pthread_create(&tid, NULL, client_handler, client_fd);
        pthread_detach(tid);
    }

    close(server_fd);
    return 0;
}
