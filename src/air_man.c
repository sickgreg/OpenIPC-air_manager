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
#include <sys/un.h> 

#define PORT 12355
#define BUF_SIZE 1024
#define CONFIRM_TIMEOUT 15 // seconds
#define DEFAULT_SCRIPT_PATH "/usr/bin/air_man_cmd.sh"
static char *script = DEFAULT_SCRIPT_PATH;

// ─── Shared protocol definitions ───
// For comms with alink
enum {
    CMD_SET_POWER      = 1,
    CMD_GET_STATUS     = 2,
    // … add more as you need
    CMD_STATUS_REPLY   = 0x8000    // OR’d into cmd for replies
};

struct __attribute__((packed)) alink_msg_hdr {
    uint16_t cmd;   // one of CMD_*
    uint16_t len;   // length of payload in bytes
};

// ────────────────────────────────────
// Path to the AF_UNIX socket used by alink
#define ALINK_CMD_SOCKET_PATH  "/tmp/alink_cmd.sock"

// Path to your alink config file to update there
#define ALINK_CONFIG_FILE      "/etc/alink.conf"

// Sends a CMD_SET_POWER TLV to alink, returns 0 on OK, 1 on out-of-range, -1 on error
static int airman_send_set_power(int new_level) {
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return -1;

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path,
            ALINK_CMD_SOCKET_PATH,
            sizeof(addr.sun_path)-1);
			
    if (connect(fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        close(fd);
        return -1;
    }

    // build request
    int32_t net_v = htonl(new_level);
    struct alink_msg_hdr hdr = {
        .cmd = htons(CMD_SET_POWER),
        .len = htons(sizeof(net_v))
    };
    if (write(fd, &hdr, sizeof(hdr)) != sizeof(hdr) ||
        write(fd, &net_v, sizeof(net_v)) != sizeof(net_v)) {
        close(fd);
        return -1;
    }

    // read reply
    if (read(fd, &hdr, sizeof(hdr)) != sizeof(hdr)) { close(fd); return -1; }
    hdr.cmd = ntohs(hdr.cmd);
    hdr.len = ntohs(hdr.len);
    if (hdr.cmd != (CMD_SET_POWER|CMD_STATUS_REPLY) || hdr.len != 4) {
        close(fd);
        return -1;
    }
    int32_t net_status;
    if (read(fd, &net_status, 4) != 4) { close(fd); return -1; }
    close(fd);

    return ntohl(net_status);  // 0=OK, 1=out-of-range
}

// Updates the alink config file’s power_level_0_to_10 via sed.
// Returns 0 on success, nonzero on failure.
static int update_alink_config_power(int new_level) {
    char cmd[256];
    // assumes a line like "power_level_0_to_10=5"
    snprintf(cmd, sizeof(cmd),
      "sed -i 's/^power_level_0_to_10=[0-9]\\+/power_level_0_to_10=%d/' %s",
      new_level, ALINK_CONFIG_FILE);
    return system(cmd);
}



// Global verbose flag
int verbose = 0;

// Global current settings
int current_channel = 0;
char current_resolution[32] = "1280x720";
int current_fps = 30;
int current_bandwidth = 20;
char bw_string[10] = "";


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
	
	strcpy(bw_string,
       current_bandwidth == 10 ? "10MHz" :
       current_bandwidth == 40 ? "HT40+" :
       current_bandwidth == 80 ? "80MHz" : "");

    snprintf(syscmd, sizeof(syscmd), "iw dev wlan0 set channel %d %s", orig_channel, bw_string);
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

			sleep(1);

			strcpy(bw_string,
				current_bandwidth == 10 ? "10MHz" :
				current_bandwidth == 40 ? "HT40+" :
				current_bandwidth == 80 ? "80MHz" : "");

			snprintf(syscmd, sizeof(syscmd), "iw dev wlan0 set channel %d %s", new_channel, bw_string);
            if (verbose) printf("[DEBUG] %s\n", syscmd);
            if (system(syscmd) == 0) {
                pthread_mutex_lock(&pending.lock);
                pending.original_channel = current_channel;
                pending.pending_channel = new_channel;
                pending.pending_channel_flag = 1;
                pending.pending_channel_time = time(NULL);
                pthread_mutex_unlock(&pending.lock);                
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

	    } else if (strncmp(command, "set_alink_power", 15) == 0) {
			int lvl;
			if (sscanf(command, "set_alink_power %d", &lvl) == 1) {
				char resp[BUF_SIZE];
				int sock_status = airman_send_set_power(lvl);
				int cfg_status  = update_alink_config_power(lvl);

				if (sock_status == 0 && cfg_status == 0) {
					snprintf(response, resp_size,
							"alink power set to %d (socket OK, config updated).",
							lvl);
				} else {
					char *part1 = (sock_status ==  0 ? "socket OK" :
								sock_status ==  1 ? "socket: value out-of-range" :
													"socket error");
					char *part2 = (cfg_status  == 0 ? "config OK" :
								"config update failed");
					snprintf(response, resp_size,
							"set_alink_power %d: %s; %s.",
							lvl, part1, part2);
				}
			} else {
				snprintf(response, resp_size,
						"Invalid usage. Format: set_alink_power <0–10>");
			}


		} else {
			char s[BUF_SIZE+128];
			// redirect stderr into stdout so popen() sees syntax errors too
			snprintf(s, sizeof(s), "%s %s 2>&1", script, command);
			if (verbose) printf("[DEBUG] Running fallback: %s\n", s);

			FILE *pipe = popen(s, "r");
			if (pipe) {
				char out[BUF_SIZE];
				response[0] = '\0';

				// grab first line of combined stdout+stderr
				if (fgets(out, sizeof(out), pipe)) {
					out[strcspn(out, "\r\n")] = 0;
					strncpy(response, out, resp_size-1);
					response[resp_size-1] = '\0';
				}
				// now check exit status
				int status = pclose(pipe);
				if (response[0]=='\0' && WIFEXITED(status) && WEXITSTATUS(status)!=0) {
					snprintf(response, resp_size,
							"Error: script exited with code %d",
							WEXITSTATUS(status));
				}
			} else {
				snprintf(response, resp_size,
						"Error executing %s", script);
			}
		}

}


// Thread function to handle each client connection.
void *client_handler(void *arg) {
    int client_fd = *(int*)arg; free(arg);
    char buffer[BUF_SIZE];
    int n = read(client_fd, buffer, sizeof(buffer)-1);
    if (n <= 0) {
        close(client_fd);
        pthread_exit(NULL);
    }
    buffer[n] = '\0';
    if (verbose) printf("[DEBUG] Received: %s\n", buffer);

    // 1) If it's a change_channel command, immediately ACK
    if (strncmp(buffer, "change_channel", 14) == 0) {
        const char *ack = 
            "Channel change command received. "
            "Attempting change and wait for confirmation.\n";
        write(client_fd, ack, strlen(ack));
    }

    // 2) Now do the full processing (this will block/sleep, etc.)
    char response[BUF_SIZE] = {0};
    process_command(buffer, response, sizeof(response));
    if (verbose) printf("[DEBUG] Responding: %s\n", response);

    // 3) Send the final result
    write(client_fd, response, strlen(response));

    close(client_fd);
    pthread_exit(NULL);
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
	char *val2 = read_yaml_value("/etc/wfb.yaml",".wireless.width");
	current_bandwidth = atoi(val2);
	
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
