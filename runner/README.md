# runner — 无人值守驱动器（可选）

框架的主控是**会话轮换制**的：每个会话最多跑「每会话 tick 上限」轮就落盘退出。谁来拉起下一个会话？两种方式：

- **有人值守**：你新开会话说「按 LOOP.md 继续」。
- **无人值守**：本目录的驱动脚本。它是十几行纯胶水——循环调用 `claude -p "按 LOOP.md 继续"`，每个会话都是全新上下文；读投影 `loop/state.md` 的 `状态` 字段判停。**脚本里没有任何调度逻辑**，调度智能全部仍在提示词与协议中，这不违背框架"编排智能在提示词"的理念，只是把"重启会话"这个人类动作自动化了。

**前置要求**：项目须为 git 仓库（worktree 事务依赖它；主控首次启动也会自行 `git init`），且运行环境能执行 `claude` CLI。

## 用法

在**项目根目录**（LOOP.md 所在目录）运行：

```powershell
# Windows
.\runner\run-loop.ps1                # 默认最多 30 个会话
.\runner\run-loop.ps1 -MaxGenerations 50
```

```bash
# macOS / Linux
./runner/run-loop.sh                 # 默认最多 30 个会话
./runner/run-loop.sh 50
```

## 判停规则（读投影 state.md 的 `状态` 字段）

| 状态 | 驱动器动作 |
|---|---|
| `finished`（或 loop/FINAL.md 已存在） | 全部完成，退出 0 |
| `waiting-human` | 需人工介入（blocked 汇总 / questions 待答 / 保险丝），退出 2 并提示看 state.md |
| `running` / 无状态文件 | 拉起下一个会话继续 |

另有两道兜底保险丝，防止外层失控循环：

- **会话数上限**：默认 30 个会话，超过即停（可调）。
- **停滞检测**：若一个会话结束后投影的 tick 数没有前进，记一次停滞；连续 2 次停滞即停（说明主控在空转或环境有问题，烧钱无进展）。

## 权限模式（须知情选择）

无人值守意味着没人守在终端按"允许"。脚本默认使用 `--permission-mode acceptEdits`（自动接受文件编辑，命令仍受项目 `.claude/settings.json` 的 allowlist 约束）。你可以：

- 预先用 `/fewer-permission-prompts` 或手工维护项目 allowlist（推荐——这是最小授权路径）；注意循环需要 `git worktree`/`git merge` 权限；
- 或改用 `-DangerouslySkipPermissions` 开关（传 `--dangerously-skip-permissions`）——**仅限可信仓库与沙箱环境**，请理解其含义后再用。

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
