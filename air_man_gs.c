#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>


const char *bash_script =
"#!/usr/bin/env bash\n"
"set -euo pipefail\n"
"\n"
"PORT=12355\n"
"VERBOSE=0\n"
"\n"
"print_help() {\n"
"  cat <<EOF\n"
"Usage:\n"
"  $0 [--verbose] <server_ip> \"<command>\"\n"
"  $0 --help\n"
"\n"
"Options:\n"
"  -v, --verbose   Enable debug output\n"
"  -h, --help      Show this help message\n"
"\n"
"Commands (use quotes for multiple words):\n"
"  start_alink\n"
"  stop_alink\n"
"  restart_majestic\n"
"  \"change_channel <n>\"\n"
"  confirm_channel_change\n"
"  \"set_alink_power <0–10>\"\n"
"  \"set_video_mode <size> <fps> <exposure> '<crop>'\"\n"
"  restart_wfb\n"
"  restart_msposd\n"
"  (and any air_man_cmd.sh commands)\n"
"EOF\n"
"}\n"
"\n"
"# Parse flags\n"
"while [[ $# -gt 0 ]]; do\n"
"  case \"$1\" in\n"
"    -v|--verbose) VERBOSE=1; shift ;;\n"
"    -h|--help)     print_help; exit 0 ;;\n"
"    --)            shift; break ;;\n"
"    -*)            echo \"Unknown option: $1\" >&2; print_help; exit 1 ;;\n"
"    *)             break ;;\n"
"  esac\n"
"done\n"
"\n"
"if [[ $# -lt 2 ]]; then\n"
"  print_help; exit 1\n"
"fi\n"
"\n"
"SERVER_IP=$1; shift\n"
"CMD=\"$1\"\n"
"\n"
"[[ $VERBOSE -eq 1 ]] && echo \"[DEBUG] Command → $CMD\"\n"
"\n"
"# Translate legacy alias\n"
"if [[ $CMD =~ ^set\\ air\\ wfbng\\ air_channel\\ ([0-9]+)$ ]]; then\n"
"  CMD=\"change_channel ${BASH_REMATCH[1]}\"\n"
"  [[ $VERBOSE -eq 1 ]] && echo \"[DEBUG] Alias → $CMD\"\n"
"fi\n"
"\n"
"# 1) Non-change_channel: try up to 3×, then exit\n"
"if [[ ! $CMD =~ ^change_channel\\ ([0-9]+)$ ]]; then\n"
"  MAX=3\n"
"  for i in $(seq 1 $MAX); do\n"
"    [[ $VERBOSE -eq 1 ]] && echo \"[DEBUG] Simple cmd attempt $i/$MAX\"\n"
"    set +e\n"
"    RESPONSE=$(printf '%s\\n' \"$CMD\" | nc -w2 \"$SERVER_IP\" $PORT)\n"
"    STAT=$?\n"
"    set -e\n"
"    if [[ $STAT -eq 0 && -n $RESPONSE ]]; then\n"
"      echo \"$RESPONSE\"\n"
"      exit 0\n"
"    fi\n"
"    sleep 0.5\n"
"  done\n"
"  echo \"No response from VTX after $MAX attempts\"\n"
"  exit 1\n"
"fi\n"
"\n"
"# 2) change_channel logic (with 3× retries on no reply)\n"
"CH=${BASH_REMATCH[1]}\n"
"[[ $VERBOSE -eq 1 ]] && echo \"[DEBUG] Sending change_channel $CH\"\n"
"\n"
"MAX_TRIES=3\n"
"SLEEP_BETWEEN=0.5\n"
"RESPONSE_LINES=()\n"
"\n"
"for (( try=1; try<=MAX_TRIES; try++ )); do\n"
"  [[ $VERBOSE -eq 1 ]] && echo \"[DEBUG] change_channel attempt $try/$MAX_TRIES\"\n"
"\n"
"  mapfile -t RESPONSE_LINES < <(\n"
"    {\n"
"      printf 'change_channel %d\\n' \"$CH\"\n"
"      sleep 2\n"
"    } | nc -w3 \"$SERVER_IP\" $PORT\n"
"  )\n"
"\n"
"  if (( ${#RESPONSE_LINES[@]} > 0 )); then\n"
"    [[ $VERBOSE -eq 1 ]] && echo \"[DEBUG] Received reply on attempt $try\"\n"
"    break\n"
"  fi\n"
"\n"
"  [[ $VERBOSE -eq 1 ]] && echo \"[DEBUG] No reply yet; sleeping ${SLEEP_BETWEEN}s\"\n"
"  sleep \"$SLEEP_BETWEEN\"\n"
"done\n"
"\n"
"if (( ${#RESPONSE_LINES[@]} == 0 )); then\n"
"  echo \"No reply from VTX on change_channel after $MAX_TRIES attempts\"\n"
"  exit 1\n"
"fi\n"
"\n"
"for line in \"${RESPONSE_LINES[@]}\"; do\n"
"  echo \"$line\"\n"
"done\n"
"\n"
"for line in \"${RESPONSE_LINES[@]}\"; do\n"
"  if [[ \"$line\" == *Failed* ]]; then\n"
"    [[ $VERBOSE -eq 1 ]] && echo \"[DEBUG] Detected failure; aborting\"\n"
"    exit 1\n"
"  fi\n"
"done\n"
"\n"
"[[ $VERBOSE -eq 1 ]] && echo \"[DEBUG] Server change_channel succeeded → proceeding with local reconfigure\"\n"
"\n"
"RAW_NICS=$(awk -F= '/^WFB_NICS/ {gsub(/\\\"/, \"\", $2); print $2; exit}' /etc/default/wifibroadcast)\n"
"[[ $VERBOSE -eq 1 ]] && echo \"[DEBUG] Raw WFB_NICS string: '$RAW_NICS'\"\n"
"read -ra NICS <<< \"$RAW_NICS\"\n"
"[[ $VERBOSE -eq 1 ]] && printf \"[DEBUG] Parsed NICS: %s\\n\" \"${NICS[@]}\"\n"
"\n"
"FIRST_NIC=\"${NICS[0]}\"\n"
"ORIG=$(iw dev \"$FIRST_NIC\" info 2>/dev/null | awk '/channel/ {print $2; exit}' || echo \"unknown\")\n"
"[[ $VERBOSE -eq 1 ]] && echo \"[DEBUG] Original local channel (on $FIRST_NIC): $ORIG\"\n"
"\n"
"RAW_BW_LINE=$(grep -E '^\\s*bandwidth' /etc/wifibroadcast.cfg || true)\n"
"[[ $VERBOSE -eq 1 ]] && echo \"[DEBUG] Raw bandwidth line: '$RAW_BW_LINE'\"\n"
"BANDWIDTH=$(awk -F= '/^\\s*bandwidth/ {gsub(/[^0-9]/, \"\", $2); print $2; exit}' /etc/wifibroadcast.cfg || echo)\n"
"[[ $VERBOSE -eq 1 ]] && echo \"[DEBUG] Parsed BANDWIDTH='$BANDWIDTH'\"\n"
"\n"
"case \"$BANDWIDTH\" in\n"
"  10) MODE=\"10MHz\" ;;\n"
"  40) MODE=\"HT40+\" ;;\n"
"  80) MODE=\"80MHz\" ;;\n"
"  *)  MODE=\"\" ;;\n"
"esac\n"
"[[ $VERBOSE -eq 1 ]] && echo \"[DEBUG] Will use channel mode: '$MODE'\"\n"
"\n"
"for nic in \"${NICS[@]}\"; do\n"
"  if [[ -n \"$MODE\" ]]; then\n"
"    [[ $VERBOSE -eq 1 ]] && echo \"[DEBUG] iw dev $nic set channel $CH $MODE\"\n"
"    iw dev \"$nic\" set channel \"$CH\" $MODE\n"
"  else\n"
"    [[ $VERBOSE -eq 1 ]] && echo \"[DEBUG] iw dev $nic set channel $CH\"\n"
"    iw dev \"$nic\" set channel \"$CH\"\n"
"  fi\n"
"done\n"
"\n"
"SUCCESS=0\n"
"for i in {{1..10}}; do\n"
"  [[ $VERBOSE -eq 1 ]] && echo \"[DEBUG] Sending confirm_channel_change attempt $i\"\n"
"  set +e\n"
"  CONFIRM=$(printf 'confirm_channel_change\\n' | nc -w1 \"$SERVER_IP\" $PORT)\n"
"  RC=$?\n"
"  set -e\n"
"\n"
"  if [[ $RC -eq 0 && -n \"$CONFIRM\" ]]; then\n"
"    echo \"$CONFIRM\"\n"
"    SUCCESS=1\n"
"    break\n"
"  fi\n"
"\n"
"  sleep 0.25\n"
"done\n"
"\n"
"if [[ $SUCCESS -eq 1 ]]; then\n"
"  [[ $VERBOSE -eq 1 ]] && echo \"[DEBUG] Got confirmation. Persisting wifi_channel $CH into config\"\n"
"  sed -i -E \"s|^\\s*wifi_channel\\s*=.*|wifi_channel = $CH|\" /etc/wifibroadcast.cfg\n"
"else\n"
"  echo \"No confirmation received. Reverting local NICs to $ORIG\"\n"
"  for nic in \"${NICS[@]}\"; do\n"
"    iw dev \"$nic\" set channel \"$ORIG\" $MODE\n"
"  done\n"
"fi\n"
"\n"
"exit 0\n";

int main(int argc, char *argv[]) {
    char script_path[] = "/tmp/tmp_wfbcmdXXXXXX.sh";
    int fd = mkstemps(script_path, 3);  // suffix = ".sh"

    if (fd == -1) {
        perror("mkstemps");
        return 1;
    }

    FILE *fp = fdopen(fd, "w");
    if (!fp) {
        perror("fdopen");
        close(fd);
        unlink(script_path);
        return 1;
    }

    fputs(bash_script, fp);
    fclose(fp);
    chmod(script_path, 0700);

    size_t cmd_len = strlen(script_path) + 1;
    for (int i = 1; i < argc; i++) {
        cmd_len += strlen(argv[i]) + 3;
    }

    char *cmd = malloc(cmd_len);
    if (!cmd) {
        perror("malloc");
        unlink(script_path);
        return 1;
    }

    strcpy(cmd, script_path);
    for (int i = 1; i < argc; i++) {
        strcat(cmd, " \"");
        strcat(cmd, argv[i]);
        strcat(cmd, "\"");
    }

    int ret = system(cmd);
    unlink(script_path);
    free(cmd);
	
	printf("\n");  // Ensures shell prompt appears on a new line
    return WEXITSTATUS(ret);
}
