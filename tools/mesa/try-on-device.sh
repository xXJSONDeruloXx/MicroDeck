#!/bin/bash
# Installs a Mesa prefix built by tools/mesa/build.sh into /opt/mesa-sxx on the device (nothing else is touched) and records what PanVK
# reports on the Mali-G31: vulkaninfo summary, features and extensions, and vkcube if installed. Results land in out/mesa/device-report.txt.
#   tools/mesa/try-on-device.sh [out/mesa/mesa-26.3.1-arm64.tar.xz]
set -euo pipefail
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/../.."
tarball=${1:-out/mesa/mesa-26.3.1-arm64.tar.xz}
report=out/mesa/device-report.txt
dev() { bash tools/dev.sh sh "$1"; }
echo "== copying $tarball"
s=$(adb devices | awk '$2 == "device" && $1 !~ /tls/ {print $1}' | head -1)
if [ -n "$s" ]; then adb -s "$s" push "$tarball" /var/tmp/mesa-sxx.tar.xz >/dev/null
else scp -q -i secrets/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$tarball" root@${DEV_HOST:-rg40xx.local}:/var/tmp/mesa-sxx.tar.xz; fi
dev 'rm -rf /opt/mesa-sxx && tar -C / -xJf /var/tmp/mesa-sxx.tar.xz && ls /opt/mesa-sxx/lib | head -4; DEBIAN_FRONTEND=noninteractive apt-get install -y -qq libxcb-keysyms1 vulkan-tools 2>&1 | tail -1'
ICD=/opt/mesa-sxx/share/vulkan/icd.d/panfrost_icd.cortex-a53.json
{
  echo "# Mesa prefix on the device, $(date -u +%FT%TZ)"
  echo "## system Mesa (before)"
  dev 'PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1 vulkaninfo --summary 2>&1 | grep -E "apiVersion|driverName|driverInfo|deviceName|conformance" | head -8'
  echo "## /opt/mesa-sxx PanVK"
  dev "PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1 VK_DRIVER_FILES=$ICD LD_LIBRARY_PATH=/opt/mesa-sxx/lib vulkaninfo --summary 2>&1 | head -30"
  echo "## features that decide DXVK (robustness2, nullDescriptor, transformFeedback, geometryShader, descriptor indexing)"
  dev "PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1 VK_DRIVER_FILES=$ICD LD_LIBRARY_PATH=/opt/mesa-sxx/lib vulkaninfo 2>&1 | grep -iE 'robustness2|nullDescriptor|transformFeedback|geometryShader|descriptorIndexing|shaderSampledImageArrayNonUniformIndexing|VK_EXT_robustness2|VK_EXT_transform_feedback|maxDescriptor' | sort -u | head -40"
  echo "## vkcube"
  dev "which vkcube >/dev/null && (cd /tmp && DISPLAY=:0 PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1 VK_DRIVER_FILES=$ICD LD_LIBRARY_PATH=/opt/mesa-sxx/lib timeout 8 vkcube --c 120 2>&1 | tail -3) || echo 'vkcube not installed'"
} | tee "$report"
echo "== report: $report"
