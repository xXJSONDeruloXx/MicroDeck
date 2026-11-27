# Sourced by run-steam.sh. The first start downloads the Steam client and Proton, which takes minutes on an
# otherwise black screen; this shows a progress window. Installers print "@@ <percent> <text>" lines.
SETUP_FIFO=${XDG_RUNTIME_DIR:-/tmp}/mdeck-setup
SETUP_PID=

setup_ui_start() {
  command -v zenity >/dev/null && [ -n "${DISPLAY:-}" ] || return 0
  trap '' PIPE
  rm -f "$SETUP_FIFO"; mkfifo "$SETUP_FIFO" || return 0
  zenity --progress --no-cancel --title="$1" --text="Starting..." --width=560 <"$SETUP_FIFO" >/dev/null 2>&1 &
  SETUP_PID=$!
  exec 9>"$SETUP_FIFO"
}

setup_ui() {  # setup_ui PERCENT TEXT
  [ -n "$SETUP_PID" ] || return 0
  { echo "$1"; echo "# $2"; } >&9 2>/dev/null || true
}

setup_ui_run() {  # runs a command, logging its output and mirroring its @@ lines into the window
  "$@" 2>&1 | tee -a "$log" | while IFS= read -r line; do
    case $line in "@@ "*) set -- ${line#@@ }; pct=$1; shift; setup_ui "$pct" "$*" ;; esac
  done
  return "${PIPESTATUS[0]}"
}

setup_ui_end() {
  [ -n "$SETUP_PID" ] || return 0
  exec 9>&-
  sleep 1; kill "$SETUP_PID" 2>/dev/null || true
  rm -f "$SETUP_FIFO"; SETUP_PID=
  trap - PIPE
}
