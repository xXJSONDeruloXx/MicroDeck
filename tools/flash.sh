#!/bin/bash
# Queues an image (default out/microdeck-rg40xx.img, or the path given) for the elevated SD writer (C:\Users\kurt\sdflash\sdflash-helper.ps1)
# and waits for it to finish. The helper only ever writes to the USB card reader.
set -euo pipefail
cd "$(dirname "$0")/.."
q=/c/Users/kurt/sdflash/queue
job=microdeck-$(date +%Y%m%d-%H%M%S)
img=${1:-out/microdeck-rg40xx.img}
[ -f "$img" ] || { echo "no $img"; exit 1; }
cp "$img" "$q/$job.img"
: > "$q/$job.go"
echo "flash: queued $job"
until [ -f "$q/$job.done" ] || [ -f "$q/$job.failed" ]; do sleep 5; done
if [ -f "$q/$job.failed" ]; then echo "flash: FAILED: $(cat "$q/$job.failed")"; exit 1; fi
rm -f "$q/$job.img"
echo "flash: done"
