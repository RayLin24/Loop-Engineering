#!/usr/bin/env bash
# Fake Worker: legal touch plus a file outside touches.
set -eu
printf 'hello\n' > src/hello.txt
printf 'evil\n' > src/evil.txt
exit 0
