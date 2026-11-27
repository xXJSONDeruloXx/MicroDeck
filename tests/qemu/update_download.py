"""End-to-end update on the QEMU virtual device: a local HTTP server plays GitHub's release API, the VM runs the real `mdeck-update apply`
(download, SHA-256 check, unpack, stage), reboots through the real initramfs install, and must come up on the new image.

  tools/vm.sh test download <microdeck-rg40xx.img.xz>   (the image to serve as the "new release")
"""
import hashlib
import http.server
import json
import os
import sys
import threading

from session import ROOT, VM

TAG = "v9.9.9"
PORT = 8099


def serve(image):
    sha = hashlib.sha256()
    with open(image, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            sha.update(chunk)
    # the updater of a release from before the rename asks for steamos-rg40xx.img.xz, the current one for microdeck-rg40xx.img.xz
    names = ["microdeck-rg40xx.img.xz", "steamos-rg40xx.img.xz"]
    api = {"tag_name": TAG, "body": "test", "assets": [
        a for name in names for a in (
            {"name": name, "browser_download_url": "http://10.0.2.2:%d/%s" % (PORT, name)},
            {"name": name + ".sha256", "browser_download_url": "http://10.0.2.2:%d/%s.sha256" % (PORT, name)})]}

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path == "/api/latest":
                body = json.dumps(api).encode()
                self.send_response(200)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            elif self.path.endswith(".sha256") and self.path[1:-7] in names:
                body = ("%s  %s\n" % (sha.hexdigest(), self.path[1:-7])).encode()
                self.send_response(200)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            elif self.path[1:] in names:
                size = os.path.getsize(image)
                self.send_response(200)
                self.send_header("Content-Length", str(size))
                self.end_headers()
                with open(image, "rb") as f:
                    while True:
                        chunk = f.read(1 << 20)
                        if not chunk:
                            break
                        self.wfile.write(chunk)
            else:
                self.send_response(404)
                self.end_headers()

        def log_message(self, *args):
            pass

    server = http.server.ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def check(vm, command, expect, what, timeout=300):
    rc, out = vm.sh(command, timeout=timeout)
    ok = expect in out
    print("%s %s: %s" % ("ok  " if ok else "FAIL", what, out.replace("\n", " | ")[-150:]))
    if not ok:
        print(VM.serial_tail(30))
        sys.exit(1)


def main():
    image = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "out", "qemu", "ci", "microdeck-rg40xx.img.xz")
    if not os.path.exists(image):
        sys.exit("need a release image to serve: %s" % image)
    server = serve(image)
    vm = VM()
    vm.wait_up(timeout=900)
    # the base is the latest published release: from before the rename its names are sxx-update, /etc/sxx-release, SXX_UPDATE_API, /home/.sxx
    old = vm.sh("test -x /usr/local/sbin/mdeck-update")[0] != 0
    upd, rel, env, key, state = (("sxx-update", "sxx-release", "sxx-update.env", "SXX_UPDATE_API", ".sxx") if old
                                 else ("mdeck-update", "mdeck-release", "mdeck-update.env", "MDECK_UPDATE_API", ".mdeck"))
    print("base release uses the %s names" % ("old (sxx)" if old else "current (mdeck)"))
    vm.sh("echo v0.0.1 > /etc/%s; echo %s=http://10.0.2.2:%d/api/latest > /etc/%s" % (rel, key, PORT, env))
    check(vm, "/usr/local/sbin/%s check" % upd, TAG, "a newer release is found")
    check(vm, "/usr/local/sbin/%s apply 2>&1 | tail -3" % upd, "staged", "download, checksum, unpack and stage", timeout=3000)
    check(vm, "cat /home/%s/update/pending; ls /home/%s/update/boot | head -3" % (state, state), TAG, "release is staged with its boot files")
    vm.reboot(timeout=3000)
    # the new image carries its own stamp: the tag on a release build, "dev" otherwise
    check(vm, "cat /etc/mdeck-release", os.environ.get("EXPECT_RELEASE", "dev"), "the new image is running (its own release stamp)")
    check(vm, "cat /home/.mdeck/update/installed/tag; ls /home/.mdeck/update", "installed", "install recorded, staging cleaned up")
    server.shutdown()
    print("download update checks passed")


if __name__ == "__main__":
    main()
