# runner — 无人值守驱动器（可选）

框架的主控是**会话轮换制**的：每个会话最多跑「每会话 tick 上限」（`ticks_per_session`，默认 3）轮就落盘退出。谁来拉起下一个会话？两种方式：

- **有人值守**：你新开会话说「按 LOOP.md 继续」。
- **无人值守**：本目录的驱动脚本。它是纯胶水——循环调用 `claude -p "按 LOOP.md 继续"`，每个会话都是全新上下文；读投影 `loop/state.md` 判停。**脚本里没有任何调度逻辑**，调度智能全部仍在提示词与协议中。

**前置要求**：项目须为 git 仓库（worktree 事务依赖它；主控首次启动也会自行 `git init`），本机 git 已配置 `user.name` 与 `user.email`（封箱提交要用），且运行环境能执行 `claude` CLI 与 `bash`（checks 脚本）。

驱动器日志里的「第 N 次拉起」只是本进程自己的计数，从 1 开始，**不是**事件流里的 `session.gen`。脚本重新运行后这个计数会归零，协议里的代次不会。

## 用法

在**项目根目录**（LOOP.md 所在目录）运行：

```powershell
# Windows
.\runner\run-loop.ps1                          # 默认最多拉起 30 次
.\runner\run-loop.ps1 -MaxGenerations 50
.\runner\run-loop.ps1 -DangerouslySkipPermissions
```

```bash
# macOS / Linux。次数和权限开关的顺序不限
./runner/run-loop.sh                           # 默认最多拉起 30 次
./runner/run-loop.sh 50
./runner/run-loop.sh --dangerously-skip-permissions
./runner/run-loop.sh 50 --dangerously-skip-permissions
```

退出码：`0` 完成，`1` 用法或环境错误（不在项目根、找不到 `claude`），`2` 等待人工，`3` 连续两次无进展，`4` 达到拉起次数上限。

解析规则可以用 `bash runner/test-parse.sh` 自检（不调用 `claude`）。Windows 上对应 `runner/test-parse.ps1`。

## 判停规则

投影里有三行是给驱动器看的，格式见 `protocol/event-spec.md`。写偏了，驱动器就不会停在该停的地方。

| 投影 | 驱动器动作 |
|---|---|
| `状态: finished` | 退出 0。终局之后如果又改了 TASKS.md，要先人工说一次「按 LOOP.md 继续」，等这行回到 `running` |
| `状态: waiting-human`（任务状态里的 `waiting_human` 也认） | 退出 2 |
| `状态: running`，或还没有投影 | 拉起下一次会话 |
| `状态` 行把三个值写在一起，或根本对不上 | 当成无法解析。不会误当成 `running` 一直跑；tick 再不前进就按停滞停下 |
| 存在 `loop/FINAL.md` 但投影写着 `running` | 以投影为准，继续。终局文件可能是上一轮留下的 |
| 没有投影、只有 `loop/FINAL.md` | 视为完成，退出 0 |

`状态` 行必须只有一个值。`tick` 只认「项目」那一行里的分子（`tick: 12/60` 里的 `12`），备忘里出现的 `tick:` 不算进展。

另有两道兜底保险丝：

- **拉起次数上限**：默认 30，超过即停（可调）。
- **停滞检测**：一次会话结束后，若 tick 分子没有变大，记一次停滞；连续 2 次即停。会话自己非零退出不立刻终止，也走这道保险丝，给瞬时故障一次机会。投影若仍写着一个**未来的** `等待租约` 时间，说明主控在等未到期的租约而不是空转，这次不记停滞。

**等待租约**：`状态` 为 `running` 且 `等待租约` 是一个未来的 UTC 时间（`2026-07-08T15:00:00Z` 这种）时，驱动器先休眠到那个时刻，单次最多 3600 秒，然后再拉起。这是冷启动时「任务已派发、回执还没到、租约还没到期」的情况。Worker 若提前写完回执，也要等到这次休眠结束才会被下一会话捡起。写 `无`、缺这行、或时间解析不了，都不休眠。

判停在每次会话**结束之后**立刻再做一次。已经变成 `finished` 或 `waiting-human` 时直接退出，不会先把这次算成停滞再多绕一圈。

## 权限模式（须知情选择）

无人值守意味着没人守在终端按「允许」。脚本默认使用 `--permission-mode acceptEdits`。这个模式会自动接受工作目录内的文件编辑，以及 `mkdir` / `rm` / `mv` 这类常见文件命令；**不会**自动放行 `git worktree`、`git add`、`git commit`、`git merge`、`git branch` 和 `bash loop/checks/...`。`dontAsk` 会直接拒绝这些未预授权的命令，不适合拿来当默认。

循环实际要跑的命令，预先写进主工作区的 `.claude/settings.json`（或只在本机生效的 `.claude/settings.local.json`）。规则语法以当前 Claude Code 文档为准，形状如下。`git add` / `git commit` 对不上 `git -C <dir> ...` 这种写法，所以协议要求主控 `cd` 进工作区再提交：

```json
{
  "permissions": {
    "allow": [
      "Bash(git worktree *)",
      "Bash(git add *)",
      "Bash(git commit *)",
      "Bash(git merge *)",
      "Bash(git branch *)",
      "Bash(git diff *)",
      "Bash(git rev-parse *)",
      "Bash(git status *)",
      "Bash(bash loop/checks/*)"
    ]
  }
}
```

一条没放行的命令会把会话卡住，驱动器只能在事后看到 tick 没前进，然后在第二次停滞时退出。也可以改用 `--dangerously-skip-permissions`（PowerShell 开关是 `-DangerouslySkipPermissions`）——**仅限可信仓库与沙箱环境**。

高风险操作（删除、部署、花钱）的最后防线永远是 TASKS.md 的 `constraints`/`effects` 与宿主权限系统，驱动器不提供额外沙箱。

## 编码须知（Windows 必读）

`run-loop.ps1` 含中文，**必须存为 UTF-8 with BOM**。Windows PowerShell 5.1 读取无 BOM 的 UTF-8 脚本时会按系统本地代码页（中文机器为 GBK）解码，导致中文变乱码、字符串里的 `{`/`-` 被误判为语法标记，报 `意外的标记"{"` 一类解析错误。

- 编辑本脚本后若用了不带 BOM 的编辑器保存，会退回该问题。VS Code 右下角选 `UTF-8 with BOM` 再保存即可。
- 快速修复某份文件的编码：
  ```powershell
  $f = ".\runner\run-loop.ps1"
  $c = [System.IO.File]::ReadAllText($f, (New-Object System.Text.UTF8Encoding($false)))
  [System.IO.File]::WriteAllText($f, $c, (New-Object System.Text.UTF8Encoding($true)))
  ```
- `run-loop.sh` 须保持 LF 换行符（勿转 CRLF）。
