#!/system/bin/sh
# mitun_ctl.sh — KernelSU MiTun Module
# User control script: start / stop / restart / status / log / reload / validate
#
# Installed to: $DATA_DIR/mitun_ctl.sh
# Usage: sh /data/adb/mitun/mitun_ctl.sh {start|stop|restart|status|log|reload|validate}

# Source common_functions.sh from the same directory, fall back to module dir
SCRIPT_DIR="$(dirname "$0")"
if [ -f "$SCRIPT_DIR/common_functions.sh" ]; then
    . "$SCRIPT_DIR/common_functions.sh"
else
    . "/data/adb/modules/mitun/common_functions.sh"
fi

_cmd="$1"

case "$_cmd" in

    start)
        start_mihomo
        ;;

    stop)
        stop_mihomo
        ;;

    restart)
        stop_mihomo
        sleep 2
        start_mihomo
        ;;

    status)
        if is_running; then
            _pid="$(read_pid)"
            echo "MiTun is running, pid=$_pid"
            echo ""
            echo "--- TUN interface ---"
            ip link show "$TUN_DEVICE" 2>/dev/null || echo "(interface not found)"
            echo ""
            echo "--- Routes via $TUN_DEVICE ---"
            ip route show table main 2>/dev/null | grep "$TUN_DEVICE" || echo "(no routes found)"
        else
            echo "MiTun is not running"
        fi
        ;;

    log)
        tail -n 50 "$LOG_FILE" 2>/dev/null || echo "Log file not found: $LOG_FILE"
        ;;

    reload)
        if ! is_running; then
            log_error "reload: MiTun is not running"
            exit 1
        fi

        _http_code=""

        # Try curl first, then fall back to wget
        if command -v curl >/dev/null 2>&1; then
            _http_code="$(curl -s -o /dev/null -w '%{http_code}' \
                -X PUT \
                -H "Authorization: Bearer $API_SECRET" \
                -H "Content-Type: application/json" \
                -d '{"path":"'"$CONFIG_PATH"'","force":true}' \
                "http://$API_HOST:$API_PORT/configs?force=true" 2>/dev/null)"
        elif command -v wget >/dev/null 2>&1; then
            _http_code="$(wget -q -O /dev/null \
                --method=PUT \
                --header="Authorization: Bearer $API_SECRET" \
                --header="Content-Type: application/json" \
                --body-data='{"path":"'"$CONFIG_PATH"'","force":true}' \
                --server-response \
                "http://$API_HOST:$API_PORT/configs?force=true" 2>&1 | \
                grep 'HTTP/' | tail -1 | awk '{print $2}')"
        else
            log_error "reload: neither curl nor wget available"
            exit 1
        fi

        if [ "$_http_code" = "204" ]; then
            log_info "reload: config reloaded successfully (HTTP 204)"
            echo "Config reloaded successfully."
        else
            log_error "reload: config reload failed (HTTP $_http_code)"
            echo "Config reload failed (HTTP $_http_code)."
            exit 1
        fi
        ;;

    validate)
        if [ ! -f "$CONFIG_PATH" ]; then
            echo "ERROR: config file not found: $CONFIG_PATH"
            exit 1
        fi

        if [ ! -x "$BIN_PATH" ]; then
            echo "ERROR: mihomo binary not found or not executable: $BIN_PATH"
            exit 1
        fi

        _val_out="$("$BIN_PATH" -t -d "$DATA_DIR" 2>&1)"
        _val_rc=$?

        if [ "$_val_rc" -ne 0 ]; then
            echo "ERROR: config validation failed:"
            echo "$_val_out"
            exit 1
        fi

        echo "Config syntax OK."

        # Check tun.enable — use context-aware grep to avoid matching dns.enable etc.
        if ! grep -q 'tun:' "$CONFIG_PATH" 2>/dev/null || \
           ! awk '/^tun:/,/^[^ ]/' "$CONFIG_PATH" 2>/dev/null | grep -q 'enable: true'; then
            echo "WARNING: tun.enable may not be true — TUN mode may be disabled"
        fi

        # Check tun.auto-route
        if ! awk '/^tun:/,/^[^ ]/' "$CONFIG_PATH" 2>/dev/null | grep -q 'auto-route: true'; then
            echo "WARNING: tun.auto-route may not be true — manual routing may be required"
        fi
        ;;

    *)
        echo "Usage: $(basename "$0") {start|stop|restart|status|log|reload|validate}"
        echo ""
        echo "  start     Start MiTun"
        echo "  stop      Stop MiTun"
        echo "  restart   Restart MiTun (stop, wait 2s, start)"
        echo "  status    Show running status, TUN interface and routes"
        echo "  log       Show last 50 lines of the log file"
        echo "  reload    Hot-reload config via API (MiTun must be running)"
        echo "  validate  Validate config.yaml syntax and TUN settings"
        exit 1
        ;;

esac
