#!/bin/bash
# Runs mdeck-membench under different zram compression algorithms, each from a fresh boot so the runs are comparable:
# set the algorithm, reboot through muOS (FEL loop), wait for Steam's library plus a settle time, run the benchmark.
#   tools/membench.sh zstd lz4 lzo-rle          results land in out/membench.csv (WORKLOAD=<appid> for a real game)
# The device must be on adb with muOS in slot 1 (see tools/fel-boot.sh).
set -uo pipefail
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/.."
OS=${OS_SERIAL:-33806c00e4f7909a}; MUOS=${MUOS_SERIAL:-0c001080c69249221d2}
SECS=${SECS:-200}; SETTLE=${SETTLE:-90}
for algo in "$@"; do
  echo "== $(date +%T) $algo: configuring"
  # "a+b" = primary a with b as the secondary for idle-page recompression (mdeck-zram-recompress)
  # "+damon" also turns on proactive reclaim of cold memory (mdeck-damon-reclaim)
  dsvc=disable; case "$algo" in *+damon*) dsvc=enable; algo_c=${algo//+damon/};; *) algo_c=$algo;; esac
  conf=${algo_c//+/ }; svc=disable; case "$algo_c" in *+*) svc=enable;; esac
  adb -s $OS shell "sed -i 's/^compression-algorithm = .*/compression-algorithm = $conf/' /etc/systemd/zram-generator.conf; systemctl $svc mdeck-zram-recompress.service >/dev/null 2>&1; systemctl $dsvc mdeck-damon-reclaim.service >/dev/null 2>&1; grep compression /etc/systemd/zram-generator.conf; sync; (systemctl reboot >/dev/null 2>&1 &)"
  until adb -s $MUOS get-state 2>/dev/null | grep -q device; do sleep 5; done
  sleep 15
  tools/fel-boot.sh > out/membench-fel.log 2>&1 || { echo "fel-boot failed for $algo"; continue; }
  echo "== $(date +%T) $algo: waiting for Steam"
  for i in $(seq 1 120); do
    adb -s $OS shell 'mdeck eval "location.pathname" 2>/dev/null' 2>/dev/null | tr -d '\r' | grep -q '^/routes/library' && break
    sleep 10
  done
  sleep "$SETTLE"
  echo "== $(date +%T) $algo: running ($SECS s)"
  adb -s $OS shell "mdeck-membench $algo $SECS ${WORKLOAD:-synthetic}" | tail -2 | tee -a out/membench.log
  adb -s $OS shell 'tail -1 /var/tmp/membench.csv' | tr -d '\r' >> out/membench.csv
done
echo "== done"; cat out/membench.csv
