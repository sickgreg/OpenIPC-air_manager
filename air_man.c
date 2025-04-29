/*
 * server.c - alink_manager: TCP server for drone
 *
 * Compile with:
 *     gcc -pthread -o alink_manager server.c
 *
 * This server listens on port 12355. On startup, it:
 *   - Reads configuration from /etc/wfb.yaml
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
#define CONFIRM_TIMEOUT 15 // seconds
#define DEFAULT_SCRIPT_PATH "/usr/bin/air_man_cmd.sh"
static char *script = DEFAULT_SCRIPT_PATH;

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

// Generic function to run yaml-cli and get output as a string
char* read_yaml_value(const char* yaml_file, const char* yaml_path) {
    char command[512];
    snprintf(command, sizeof(command), "yaml-cli -i %s -g %s", yaml_file, yaml_path);

    FILE* fp = popen(command, "r");
    if (!fp) { perror("popen failed"); return NULL; }

    char buffer[BUF_SIZE];
    if (!fgets(buffer, sizeof(buffer), fp)) { pclose(fp); return NULL; }
    pclose(fp);

    buffer[strcspn(buffer, "\r\n")] = 0;
    char* result = malloc(strlen(buffer) + 1);
    if (result) strcpy(result, buffer);
    return result;
}

// Command functions: return 0 on success, non-zero on failure
int cmd_start_alink(void) {
    return system("/usr/bin/alink_drone > /dev/null &");
}

int cmd_stop_alink(void) {
    return system("killall alink_drone");
}

int cmd_restart_alink(void) {
    char *value = read_yaml_value("/etc/wfb.yaml", ".wireless.link_control");
    if (!value) {
        if (verbose) printf("[DEBUG] Could not read link_control\n");
        return -1;
    }
    int ret = -1;
    if (strcmp(value, "alink") == 0) {
        ret = system("killall alink_drone");
        if (ret == 0)
            ret = system("/usr/bin/alink_drone > /dev/null &");
    } else if (verbose) {
        printf("[DEBUG] alink not enabled in YAML (link_control=%s)\n", value);
    }
    free(value);
    return ret;
}

int cmd_restart_majestic(void) {
    return system("killall -HUP majestic");
}

int cmd_restart_wfb(void) {
    return system("sh -c \"wifibroadcast stop && sleep 1 && wifibroadcast start && sleep 2 && curl localhost/request/idr\"");
}

int cmd_restart_msposd(void) {
    return system("wifibroadcast restart osd");
}

// Helper to revert channel change on timeout
void revert_channel_change(int orig_channel) {
    char syscmd[128];
    snprintf(syscmd, sizeof(syscmd), "iw dev wlan0 set channel %d", orig_channel);
    if (verbose) printf("[DEBUG] Reverting channel: %s\n", syscmd);
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
        if (pending.pending_channel_flag && difftime(now, pending.pending_channel_time) >= CONFIRM_TIMEOUT) {
            if (verbose) printf("[DEBUG] Channel change confirmation timed out\n");
            revert_channel_change(pending.original_channel);
            pending.pending_channel_flag = 0;
        }
        pthread_mutex_unlock(&pending.lock);
    }
    return NULL;
}

/*
 * update_precrop_rc_local_simple() updates /etc/rc.local for precrop settings.
 */
void update_precrop_rc_local_simple(const char *crop) {
    char cmd[512];
    snprintf(cmd, sizeof(cmd),
             "sed -i '/^#set by alink_manager/,/echo setprecrop/{/echo setprecrop/{N; s/\\n[[:space:]]*//;};d}' /etc/rc.local");
    if (system(cmd) != 0) {
        fprintf(stderr, "Error removing old precrop blocks.\n");
        return;
    }
    if (strcmp(crop, "nocrop") == 0) return;
    snprintf(cmd, sizeof(cmd),
             "sed -i '/^[[:space:]]*exit 0[[:space:]]*$/i\\\n"
             "#set by alink_manager\\\n"
             "sleep 2\\\n"
             "echo setprecrop %s > /proc/mi_modules/mi_vpe/mi_vpe0\\\n' /etc/rc.local", crop);
    if (system(cmd) != 0) fprintf(stderr, "Error inserting new precrop block.\n");
}

// Process a command from a client and fill the response.
void process_command(const char *cmd, char *response, size_t resp_size) {
    char command[BUF_SIZE];
    strncpy(command, cmd, BUF_SIZE);
    command[strcspn(command, "\r\n")] = 0;
    if (verbose) printf("[DEBUG] Processing: %s\n", command);

    if (strncmp(command, "start_alink", 11) == 0) {
        int ret = cmd_start_alink();
        snprintf(response, resp_size,
                 ret == 0 ? "alink started." : "Error starting alink.");

    } else if (strncmp(command, "stop_alink", 10) == 0) {
        int ret = cmd_stop_alink();
        snprintf(response, resp_size,
                 ret == 0 ? "alink_drone stopped." : "Error stopping alink_drone.");

    } else if (strncmp(command, "restart_alink", 13) == 0) {
        int ret = cmd_restart_alink();
        snprintf(response, resp_size,
                 ret == 0 ? "alink_drone restarted." : "Error restarting alink_drone.");

    } else if (strncmp(command, "restart_majestic", 16) == 0) {
        int ret = cmd_restart_majestic();
        snprintf(response, resp_size,
                 ret == 0 ? "majestic restarted." : "Error restarting majestic.");

    } else if (strncmp(command, "restart_wfb", 11) == 0) {
        int ret = cmd_restart_wfb();
        snprintf(response, resp_size,
                 ret == 0 ? "wfb restarted successfully." : "Error restarting wfb.");

    } else if (strncmp(command, "restart_msposd", 14) == 0) {
        int ret = cmd_restart_msposd();
        snprintf(response, resp_size,
                 ret == 0 ? "msposd restarted." : "Error restarting msposd.");

    } else if (strncmp(command, "change_channel", 14) == 0) {
        int new_channel;
        if (sscanf(command, "change_channel %d", &new_channel) == 1) {
            char syscmd[128];
            snprintf(syscmd, sizeof(syscmd), "iw dev wlan0 set channel %d", new_channel);
            if (verbose) printf("[DEBUG] %s\n", syscmd);
            if (system(syscmd) == 0) {
                pthread_mutex_lock(&pending.lock);
                pending.original_channel = current_channel;
                pending.pending_channel = new_channel;
                pending.pending_channel_flag = 1;
                pending.pending_channel_time = time(NULL);
                pthread_mutex_unlock(&pending.lock);
                snprintf(response, resp_size,
                         "Channel change executed. Awaiting ground station confirmation.");
            } else {
                snprintf(response, resp_size, "Failed to change channel.");
            }
        } else {
            snprintf(response, resp_size, "Invalid channel command.");
        }

    } else if (strncmp(command, "confirm_channel_change", 22) == 0) {
        pthread_mutex_lock(&pending.lock);
        if (pending.pending_channel_flag) {
            current_channel = pending.pending_channel;
            char persist[128];
            snprintf(persist, sizeof(persist),
                     "yaml-cli -i /etc/wfb.yaml -s .wireless.channel %d", current_channel);
            if (verbose) printf("[DEBUG] %s\n", persist);
            system(persist);
            pending.pending_channel_flag = 0;
            pthread_mutex_unlock(&pending.lock);
            snprintf(response, resp_size,
                     "Channel change confirmed. Now on channel %d.", current_channel);
        } else {
            pthread_mutex_unlock(&pending.lock);
            snprintf(response, resp_size,
                     "No pending channel change to confirm.");
        }

    } else if (strncmp(command, "set_video_mode", 14) == 0) {
        char size[32], crop[128];
        int new_fps, new_exp;
        if (sscanf(command, "set_video_mode %31s %d %d '%127[^']'", 
                   size, &new_fps, &new_exp, crop) == 4) {
            /* Save original settings */
            char old_size[32] = "", old_fps[16] = "", old_exp[16] = "";
            FILE *p;
            p = popen("cli -g .video0.size", "r");
            if (p && fgets(old_size, sizeof(old_size), p))
                old_size[strcspn(old_size, "\r\n")] = 0;
            if (p) pclose(p);
            p = popen("cli -g .video0.fps", "r");
            if (p && fgets(old_fps, sizeof(old_fps), p))
                old_fps[strcspn(old_fps, "\r\n")] = 0;
            if (p) pclose(p);
            p = popen("cli -g .isp.exposure", "r");
            if (p && fgets(old_exp, sizeof(old_exp), p))
                old_exp[strcspn(old_exp, "\r\n")] = 0;
            if (p) pclose(p);

            /* Set new settings */
            char cmdline[256];
            snprintf(cmdline, sizeof(cmdline), "cli -s .video0.size %s", size);
            system(cmdline);
            snprintf(cmdline, sizeof(cmdline), "cli -s .video0.fps %d", new_fps);
            system(cmdline);
            snprintf(cmdline, sizeof(cmdline), "cli -s .isp.exposure %d", new_exp);
            system(cmdline);

            /* Prepare reply early */
            snprintf(response, resp_size,
                     "Video mode set. Original was size=%s fps=%s exp=%s.",
                     old_size[0] ? old_size : "?",
                     old_fps[0] ? old_fps : "?",
                     old_exp[0] ? old_exp : "?");

            /* Fork child to restart services in background */
            if (fork() == 0) {
                system("killall -HUP majestic");

                size_t len = strlen(crop);
                if (len >= 2 && ((crop[0] == '\'' && crop[len-1] == '\'') ||
                                 (crop[0] == '"' && crop[len-1] == '"'))) {
                    crop[len-1] = '\0';
                    memmove(crop, crop + 1, len - 1);
                }
                if (strcmp(crop, "nocrop") != 0) {
                    sleep(3);
                    char c2[256];
                    snprintf(c2, sizeof(c2),
                             "echo setprecrop %s > /proc/mi_modules/mi_vpe/mi_vpe0", crop);
                    system(c2);
                }
                update_precrop_rc_local_simple(crop);

                cmd_restart_msposd();
                sleep(1);
                cmd_restart_alink();
                _exit(0);
            }
        } else {
            snprintf(response, resp_size,
                     "Invalid set_video_mode command. Format: set_video_mode <size> <fps> <exposure> '<crop>'");
        }

    } else {
        char s[BUF_SIZE + 64];
        snprintf(s, sizeof(s), "%s %s", script, command);
        FILE *pipe = popen(s, "r");
        if (pipe) {
            char out[BUF_SIZE];
            if (fgets(out, sizeof(out), pipe)) {
                out[strcspn(out, "\r\n")] = 0;
                strncpy(response, out, resp_size - 1);
                response[resp_size - 1] = '\0';
            } else {
                response[0] = '\0';
            }
            pclose(pipe);
        } else {
            snprintf(response, resp_size, "Error executing air_man script.");
        }
    }
}


// Thread function to handle each client connection.
void *client_handler(void *arg) {
    int client_fd = *(int*)arg; free(arg);
    char buffer[BUF_SIZE];
    int n = read(client_fd,buffer,sizeof(buffer)-1);
    if (n>0) {
        buffer[n]='\0'; char response[BUF_SIZE];
        if (verbose) printf("[DEBUG] Received: %s\n",buffer);
        process_command(buffer,response,sizeof(response));
        if (verbose) printf("[DEBUG] Responding: %s\n",response);
        write(client_fd,response,strlen(response));
    }
    close(client_fd); pthread_exit(NULL);
}

int main(int argc,char *argv[]) {
    int opt;
    while ((opt=getopt(argc,argv,"vs:-:"))!=-1) {
        if (opt=='v') verbose=1;
        else if (opt=='s') script=optarg;
        else if (opt=='-'&&strcmp(optarg,"verbose")==0) verbose=1;
        else if (opt=='-'&&strncmp(optarg,"script=",7)==0) script=optarg+7;
    }
    if (verbose) fprintf(stderr,"[DEBUG] Starting server in verbose mode.\n");
    char *val = read_yaml_value("/etc/wfb.yaml",".wireless.channel");
    current_channel = val?atoi(val):165; if(val)free(val);

    init_pending_changes();
    pthread_t tid; pthread_create(&tid,NULL,confirmation_checker,NULL); pthread_detach(tid);

    int server_fd = socket(AF_INET,SOCK_STREAM,0);
    if (server_fd<0) { perror("socket failed"); exit(EXIT_FAILURE); }
    int optv=1;
    setsockopt(server_fd,SOL_SOCKET,SO_REUSEADDR,&optv,sizeof(optv));
    setsockopt(server_fd,SOL_SOCKET,SO_REUSEPORT,&optv,sizeof(optv));

    struct sockaddr_in addr={.sin_family=AF_INET,.sin_addr.s_addr=INADDR_ANY,.sin_port=htons(PORT)};
    if (bind(server_fd,(struct sockaddr*)&addr,sizeof(addr))<0) { perror("bind failed"); close(server_fd); exit(EXIT_FAILURE); }
    if (listen(server_fd,10)<0) { perror("listen failed"); close(server_fd); exit(EXIT_FAILURE); }
    printf("alink_manager server running on port %d\n",PORT);

    while (1) {
        struct sockaddr_in caddr; socklen_t len=sizeof(caddr);
        int *cfd = malloc(sizeof(int)); if(!cfd){perror("malloc"); continue;}
        if ((*cfd=accept(server_fd,(struct sockaddr*)&caddr,&len))<0) { perror("accept"); free(cfd); continue; }
        if (verbose) {
            char ip[INET_ADDRSTRLEN]; inet_ntop(AF_INET,&caddr.sin_addr,ip,sizeof(ip));
            fprintf(stderr,"[DEBUG] Conn from %s:%d\n",ip,ntohs(caddr.sin_port));
        }
        pthread_t t; pthread_create(&t,NULL,client_handler,cfd); pthread_detach(t);
    }
    close(server_fd); return 0;
}
