#!/usr/bin/env bash
# Fake Worker: sleep so the test harness can kill the runner after dispatched.
set -eu
sleep 20
printf 'hello\n' > src/hello.txt
exit 0
