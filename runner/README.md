# runner — 无人值守驱动器（可选）

框架的主控是**代际制**的：每代会话最多跑「每代最大轮次」轮就落盘退出。谁来拉起下一代？两种方式：

- **有人值守**：你新开会话说「按 LOOP.md 继续」。
- **无人值守**：本目录的驱动脚本。它是十几行纯胶水——循环调用 `claude -p "按 LOOP.md 继续"`，每代都是全新会话、干净上下文；读 `loop/state.md` 的 `循环状态` 判停。**脚本里没有任何调度逻辑**，调度智能全部仍在提示词与协议中，这不违背框架"编排智能在提示词"的理念，只是把"重启会话"这个人类动作自动化了。

## 用法

在**项目根目录**（LOOP.md 所在目录）运行：

```powershell
# Windows
.\runner\run-loop.ps1                # 默认最多 30 代
.\runner\run-loop.ps1 -MaxGenerations 50
```

```bash
# macOS / Linux
./runner/run-loop.sh                 # 默认最多 30 代
./runner/run-loop.sh 50
```

## 判停规则（读 state.md 的 `循环状态`）

| 状态 | 驱动器动作 |
|---|---|
| `finished`（或 loop/FINAL.md 已存在） | 全部完成，退出 0 |
| `awaiting-human` | 需人工介入（blocked 汇总 / 保险丝 / 升级事项），退出 2 并提示看 state.md |
| `handoff` / `running` / 无状态文件 | 拉起下一代会话继续 |

另有两道兜底保险丝，防止外层失控循环：

- **代数上限**：默认 30 代，超过即停（可调）。
- **停滞检测**：若一代会话结束后 state.md 的 `轮次` 没有前进，记一次停滞；连续 2 次停滞即停（说明主控在空转或环境有问题，烧钱无进展）。

## 权限模式（须知情选择）

无人值守意味着没人守在终端按"允许"。脚本默认使用 `--permission-mode acceptEdits`（自动接受文件编辑，命令仍受项目 `.claude/settings.json` 的 allowlist 约束）。你可以：

- 预先用 `/fewer-permission-prompts` 或手工维护项目 allowlist（推荐——这是最小授权路径）；
- 或改用 `-DangerouslySkipPermissions` 开关（传 `--dangerously-skip-permissions`）——**仅限可信仓库与沙箱环境**，请理解其含义后再用。

高风险操作（删除、部署、花钱）的最后防线永远是 TASKS.md 的 `constraints` 与宿主权限系统，驱动器不提供额外沙箱。
