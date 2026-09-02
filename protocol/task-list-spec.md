# 任务清单规范（min-loop v0）

`TASKS.md` 是循环的唯一输入，由人类编写。字段、语义与 runner 用法以仓库根目录 [MIN-LOOP.md](../MIN-LOOP.md) **§2** 为准。本页只做对照，不增加字段。

循环运行期间 Worker **不得**改 `TASKS.md`。人可以随时改；runner 每个 tick 开始时重读。任务状态不写在清单里，由 `loop/events.jsonl` 重放得到。

## 骨架

```markdown
# 任务清单：<项目名>

## 全局上下文
<≤30 行，所有任务都需要的背景。密钥只写环境变量名。>

## 任务

### [T1] <标题>
id: T1
depends_on: []
touches:
  - src/foo.py
checks:
  - python -m pytest tests/test_foo.py -q
context_files:
  - src/foo.py
<正文：给「只看见本任务」的 Worker。>
```

## 字段（与 MIN-LOOP.md §2 相同）

| 字段 | 必填 | runner 怎么用 |
|---|---|---|
| `id` | 是 | `T` + 数字，与标题 `[T1]` 一致 |
| `depends_on` | 是 | 列表全为 `done` 才就绪；启动时检环，有环则停并写 `NEED_HUMAN.md` |
| `touches` | 是 | 目录以 `/` 结尾。merge 前 `git diff --name-only` 必须 ⊆ 此集合（前缀包含算命中） |
| `checks` | 是 | 每条是一条 shell。在即将 merge 的工作区里执行；非 0 则本 tick 失败。成功落地后，全部已 `done` 任务的 checks 再跑一遍 |
| `context_files` | 否 | 写进 Worker 简报；只列文件不列目录 |
| 正文 | 是 | 只给 Worker，不进状态机 |

v0 不使用：`acceptance`、`constraints`、`resources`、`timeout`、`risk`、`effects`。

示例：`examples/TASKS.example.md`。
