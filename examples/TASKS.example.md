# 任务清单：min-loop-toy

## 全局上下文
Two sequential file tasks for min-loop v0. No secrets. Checks are ordinary shell commands.
Keep edits inside each task's touches.

## 任务

### [T1] Write hello marker
id: T1
depends_on: []
touches:
  - src/hello.txt
checks:
  - test -f src/hello.txt
  - grep -qx hello src/hello.txt
context_files:
  - src/hello.txt
Write exactly the line `hello` (no extra words) into `src/hello.txt`. Do not create other files.

### [T2] Write world marker
id: T2
depends_on: [T1]
touches:
  - src/world.txt
checks:
  - test -f src/world.txt
  - grep -qx world src/world.txt
context_files:
  - src/world.txt
Write exactly the line `world` into `src/world.txt`. T1 must already be done. Do not edit `src/hello.txt`.
