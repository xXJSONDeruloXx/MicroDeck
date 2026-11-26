#!/bin/bash
# Fast checks that need no device and no image build: every script parses, then the unit tests run.
#   tools/ci-checks.sh
set -u
cd "$(dirname "$0")/.."
fail=0
note() { echo "FAIL $*"; fail=1; }

while IFS= read -r f; do
  first=$(head -c 200 "$f" 2>/dev/null | head -n1 | tr -d '\r')
  case "$first" in
    '#!/bin/bash'*|'#!/usr/bin/env bash'*) bash -n "$f" 2>&1 || note "bash syntax: $f" ;;
    '#!/bin/sh'*|'#!/bin/busybox sh'*)     sh -n "$f" 2>&1 || note "sh syntax: $f" ;;
    '#!/usr/bin/python3'*|'#!/usr/bin/env python3'*|'#!/usr/bin/env python'*)
      python3 -c 'import ast,sys; ast.parse(open(sys.argv[1], encoding="utf-8").read(), sys.argv[1])' "$f" 2>&1 || note "python syntax: $f" ;;
  esac
done < <(find overlay debug tools kernel uboot rootfs -type f ! -name '*.md' ! -name '*.c' ! -name '*.json' ! -name '*.conf' ! -name '*.service' 2>/dev/null)

python3 -m unittest discover -s tests -p 'test_*.py' || note "unit tests"
[ "$fail" = 0 ] && echo "ci-checks: ok"
exit "$fail"
