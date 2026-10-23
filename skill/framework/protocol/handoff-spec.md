# 主从交接协议（handoff-spec）

主控、Worker 与 Verifier 之间**只通过三种文件**通信：简报（brief，主控→Worker）、回执（report，Worker→主控）、裁决（verdict，Verifier→主控；其输入是主控写的验证简报）。禁止任何隐式信息传递（如"Worker 应该记得上一轮……"——Worker 没有上一轮，每个 Worker、每个 Verifier 都是全新上下文）。

**简报是指针，不是拷贝**。简报只写「阅读清单」——指向信息所在的文件与节；读取与装配由收件的 Worker/Verifier 自己完成。理由是预算不对称：主控是全循环最稀缺的上下文，Worker/Verifier 是一次性上下文——同样的信息装配工作，发生在后者身上近乎免费，发生在主控身上则直接缩短这个会话的寿命。主控在简报中亲笔书写的只有判断性内容：调度附言、命令授权、失败反思。

**重试归档规则**：三类文件都按 `<task-id>.md` 命名，指向**当前尝试**。派发重试前，主控必须先把上一次尝试的简报、回执、裁决重命名归档为 `<task-id>.attempt<n>.md`（n 为上次的尝试次数），再写新简报。失败历史因此完整保留——blocked 升级时的失败史汇总、反思的撰写，都以归档文件为依据。

## 简报格式：`loop/briefs/<task-id>.md`

由主控在派发前生成。模板：

```markdown
# 任务简报: <task-id> <任务标题>
- 尝试: 1 | 时限: 30m | 主干: <base>
- 工作区: <主工作区绝对路径>/.loop-worktrees/<task-id>-a<n>
- 主工作区: <主工作区绝对路径>
- 回执: <主工作区绝对路径>/loop/reports/<task-id>.md

## 阅读清单（下列路径都相对主工作区, 不是工作区 cwd）
1. TASKS.md：「全局上下文」节 + 「[<task-id>]」任务节（含 yaml 与正文）。
   其余任务节是禁区——先定位行号再按范围读, 不要整读。
2. 上游回执：loop/reports/<依赖id>.md（每个 depends_on 一行;
   只读「关键决策」与「对下游的提醒」）  <!-- 无依赖则删除本行 -->
3. loop/decisions.md：只读 scope 为 [global] 及 <相关 scope> 的条目
   <!-- 不存在或没有相关 scope 则删除本行 -->
4. loop/lessons.md   <!-- 运行配置 lessons=off 时删除本行 -->
5. loop/questions/<task-id>.md   <!-- 仅 waiting_human 恢复时保留 -->

## 主控附言
无

## 上次失败的反思  <!-- 仅重试时包含, 主控亲笔, 不计入行数上限 -->
<上次未通过的标准 → 原因分析(以裁决 ❌ 条目与「修复建议」为依据) → 本次应改变的做法>
```

**路径纪律**：Worker 的 cwd 是「工作区」。`git worktree add` 得到的新检出**不会**带上被 gitignore 的 `loop/`。在 cwd 里按相对路径写 `loop/reports/<id>.md`，会落到工作区里的另一份目录，主控在主工作区读不到，下一轮就判 `report_missing`。阅读清单和回执一律走简报里的主工作区绝对路径。产出物仍然只写工作区里的 `touches`。「主干」是 `dispatched.base`（派发时的 `git rev-parse --abbrev-ref HEAD`；游离 HEAD 时改为当时的 commit sha），不要写死 `main`。

**生成纪律**：

- 除「上次失败的反思」外，简报 ≤25 行。未用到的可选行整行删除，不要留占位。禁止把 TASKS.md、上游回执、decisions.md 的内容抄进简报。
- 「主控附言」承载调度层信息：备忘中与本任务相关的提醒、中断残留警告、临时资源约束。不得篡改验收标准、不得替 Worker 预设实现方案。
- 「上次失败的反思」是主控亲笔的判断性内容，禁止无反思的原样重发。

## 回执格式：`loop/reports/<task-id>.md`

由 Worker 在结束前写出（无论成败）。**回执写到简报「回执」字段给出的主工作区绝对路径**（不是 worktree 内——worktree 只放产出物，而且里面没有主仓库那份 `loop/`）。这是 Worker 留给世界的唯一遗产——它的上下文即将销毁，一切有价值的信息必须写在这里。模板：

```markdown
# 回执: <task-id>
- 结果: 完成 | 未完成
- 自查: <逐条对照验收标准, 每条标注 ✅/❌ 及一句话证据>

## 产出物
<创建/修改的文件列表（worktree 内相对路径）, 每个文件一句话说明>

## 关键决策
<执行中做出的、会影响后续任务的技术选择, 每条一行并带 [scope] 前缀。
 scope 是决策的作用域标签: global, 或一个与产出物路径/领域相关的小写短词
 (如 naming / data / api / ui / build)。
 例如: "[naming] 日期格式统一用 ISO 8601"。没有则写"无">

## 对下游的提醒
<下游任务使用我的产出时需要知道的事: 接口约定、已知限制、坑。没有则写"无">

## 遗留问题  <!-- 未完成或部分完成时必填 -->
<什么没做完、卡在哪里、缺什么信息或权限>
```

**回执的上下文纪律**：回执全文必须 ≤60 行——**主控只读前 60 行，超出部分对主控不存在**（预算由读者端强制执行）。它是摘要不是日志：主控永不读产出物全文，回执写不清楚的信息对主控就是不存在的。

## 验证简报格式：`loop/briefs/<task-id>.verify.md`

由主控在派发 Verifier 前生成。同样是指针式。模板：

```markdown
# 验证简报: <task-id> <任务标题>
- 工作区: <主工作区绝对路径>/.loop-worktrees/<task-id>-a<n>
- 主工作区: <主工作区绝对路径>
- 裁决: <主工作区绝对路径>/loop/verdicts/<task-id>.md

## 验证依据（按序读取; 路径相对主工作区, cwd 是工作区）
1. TASKS.md：「全局上下文」节（通用约束）+ 「[<task-id>]」任务节
   （acceptance 逐条核查; constraints 与 touches 同为核查对象）。其余任务节是禁区。
2. 回执 loop/reports/<task-id>.md：只读「产出物」与「关键决策」两节
   （用于圈定核查范围与重点部位）。不要参照其自查结论——你的价值在于独立重查。

## 禁读清单（评判独立性红线）
- loop/lessons.md 与 loop/decisions.md（经验与决策只影响提案, 不得影响评判）
- loop/briefs/<task-id>*.md（任务简报, 含失败叙事）与 loop/verdicts/ 下任何历史裁决

## 授权验证命令
- acceptance 中出现的构建/测试/grep 等机械验证命令, 视为已授权（在 worktree 内运行）
- <主控额外授权的读操作, 如起本地 dev server 查看页面; 无则删除本行>

## 附加约束  <!-- 主控调度层补充, 如"本次为复核, 构建前先 clean"; 无则写"无" -->
无
```

## 裁决格式：`loop/verdicts/<task-id>.md`

由 Verifier 在结束前写出，写到验证简报「裁决」字段给出的主工作区绝对路径。模板：

```markdown
# 裁决: <task-id>
- 总裁决: 通过 | 不通过

## 逐条核查
<每条验收标准与约束一行: ✅/❌/⚠️(无法验证) + 一句话证据。
 ❌ 条目必须写明: 哪个文件/哪个场景、观察到什么、与预期的差异>

## 修复建议  <!-- 仅不通过时必填 -->
<2-3 行: 基于你读过的产出物全文, 指出问题根源与建议的修复方向。
 你是唯一读过全文的角色, 主控将以此为主要依据撰写重试反思>

## 备注  <!-- 可省略 -->
<⚠️ 条目的原因、核查中发现的验收标准之外的隐患>
```

**裁决的上下文纪律**：裁决全文 ≤30 行——**主控只读前 30 行，超出部分对主控不存在**。存在任一 ❌ 时总裁决必须为"不通过"；⚠️ 不导致不通过，但主控须记入日志。单任务 ⚠️ 条目超过标准总数一半时，主控不得静默标记 done，应升级询问用户（走 questions 通道）。

## 验收流程（主控侧）

同一轮只验收本轮派发的任务。失败的任务要到**下一轮**才带着反思重派，不要在同一轮里当场再派一次。

1. 读回执（只读前 60 行）。回执缺失或格式残缺 → 失败收尾（`class: report_missing`，计重试）。这种情况下**不要**追加 `report` 事件。
2. 回执报告任务超出单次上下文可完成范围 → 走 questions 通道建议拆分，追加 `task_waiting`（不计重试），失败收尾时只丢弃工作区、不再追加 `task_failed`，不派 Verifier。
3. 核对自查表：Worker 自报有 ❌ → 失败收尾（`class: honest`，该任务首次不计重试），跳过 Verifier。
4. **独立验证**：写指针式验证简报，派发 Verifier（指令："读 `prompts/verifier.md` 并遵守其中规则，然后执行 `loop/briefs/<id>.verify.md` 描述的验证"），读回裁决（只读前 30 行）。**验证互斥**：共享 `resources` 标签的任务，其 Verifier 不得与同标签任务的 Worker 或 Verifier 同时在途（端口、数据库等真共享资源仍须互斥；构建产物目录已由 worktree 天然隔离）。
5. 裁决"通过" → 进入**工作区事务**的合并流程（见下节）。合并成功且 checks 全绿 → 追加 `task_done`。"不通过"或裁决缺失 → 失败收尾（`class: acceptance`，原因取自裁决 ❌ 条目）。「上次失败的反思」以裁决的 ❌ 条目与「修复建议」为主要依据。

**失败收尾**：`git worktree remove --force`（目录不存在视为清理成功）+ `git branch -D`（分支不存在同样忽略），追加 `discarded` 与 `task_failed`。确定性失败达到重试上限时再追加 `task_blocked`。半成品不保留。走 questions 升级时只丢弃工作区并追加 `discarded` 与 `task_waiting`，不再追加 `task_failed`。

## 工作区事务（worktree transaction）

每个任务的每次尝试都在**独立 git worktree** 中执行，落地即合并，失败即丢弃。这把"越界写入"从事后抽查变成结构化检查，把并行冲突显式化为合并冲突。

- **创建（先写后做）**：先追加 `dispatched`（含 `attempt`、`lease_expires`、`worktree`、`base`），**再**执行 `git worktree add .loop-worktrees/<id>-a<n> -b loop/<id>-a<n>`。`base` 是此时的主干分支名（`git rev-parse --abbrev-ref HEAD`；若是 `HEAD` 这种游离状态，改记 `git rev-parse HEAD`）。worktree 创建失败 → 失败收尾（`class: transient`，不计重试）并 `note` 记下命令输出，不要干等租约。不要 `git checkout` 这条任务分支：它正被该 worktree 占用，git 会拒绝。
- **封箱提交（合并前，主控做）**：Worker 被禁止 commit，未提交的改动对 `git diff <base>...branch` **不可见**，直接 merge 会得到空合并。裁决通过后，在工作区目录内执行（用 `cd` 进去，不要写成 `git -C ...`，以便对上 `git add` / `git commit` 这种权限规则）：

  ```bash
  git add -A
  git commit -m "loop: <id> attempt <n>"
  ```

  没有改动可提交 → 失败收尾（`class: acceptance`，计重试，理由写明工作区是空的）。因未配置 `user.name` / `user.email` 或权限失败而提交不了 → 丢弃工作区，走 questions 通道 + `task_waiting`（不计重试），不要当成 transient 反复重试。
- **越界检查（合并前）**：`git diff --name-only <base>...loop/<id>-a<n>` 的文件列表必须是该任务 `touches` 的子集。出现范围外文件 → 不合并，失败收尾（`class: constraint`），反思中点名越界文件。**清单笔误特例**：若 touches 中某路径在项目中不存在，且 diff 路径与任务目标明显对应（典型：清单写错目录名），主控**不修改 TASKS.md**，而是追加 `note` 登记「Tn touches 笔误：清单写 X，实际为 Y」，本次验收与后续并行判定按实际路径执行，并在 FINAL 遗留问题中提请人类修正清单。
- **合并（落地）**：越界检查通过后，在主工作区执行 `git merge --no-ff -m "loop: land <id> a<n>" loop/<id>-a<n>`。必须带 `-m`，避免 `GIT_MERGE_AUTOEDIT` 一类配置弹出编辑器把无人值守会话卡住。成功则追加 `landed`（`commit` 填这次合并提交的哈希），然后 `git worktree remove` 该目录、`git branch -d` 该分支。合并前主工作区必须是干净的（循环内落地串行执行，天然满足）。`landed` 是记录事件，任务要等 checks 通过才进入 `done`。
- **合并冲突**：`git merge --abort`，失败收尾（`class: conflict, counts_retry: false`），随下一轮重派（新 worktree 基于最新主干）。先到先落地，后到者被拒重来。
- **失败丢弃**：验收不通过、回执缺失、越界、租约超时、封箱失败，工作区一律按「失败收尾」丢掉。租约超时的 `class` 仍是 `transient` 且不计重试；同一任务连续 2 次租约超时则 `task_blocked`（见 event-spec）。
- **checks 编译**：合并成功后，主控从该任务 acceptance 中抽出**机械可执行条目**（命令、文件存在性、grep 断言）生成 `loop/checks/<task-id>.sh`（`set -euo pipefail`，逐条断言，任一失败则非零退出；纯主观标准不编入）。没有机械条目就不创建文件，不要写一个永远成功的空壳来占位。
- **回归保护**：编译之后，**逐个**执行 `loop/checks/` 下已有的 `*.sh`。工作目录是主工作区，命令形如 `bash loop/checks/T1.sh`，输出追加到 `loop/checks/last-run.log`，主控只看每个脚本的退出码；非零时才读该次日志尾部 ≤20 行。没有脚本 → 视为通过。禁止 `bash loop/checks/*.sh`：目录为空时 glob 不展开，bash 会以 127 失败；目录里有多个文件时，bash 只执行第一个，其余被当成参数。每个被破坏的**已完成**任务各追加一条 `regression`（`task` = 被破坏的任务，`caused_by` = 本次落地的任务，`failed_checks` 列出脚本名），本次落地任务记 `task_failed`（`class: acceptance`）——破坏者负责修复，被破坏任务保持 done。只有本任务刚编译的脚本失败时，追加 `checks`（`pass: false`）和 `task_failed`（`class: acceptance`，理由写明首跑失败），**不要**发 `regression`。全部通过 → `checks`（`pass: true`），回执「关键决策」逐条追加 `decision`，再追加 `task_done`。疑似 checks 本身因环境失效（缓存、残留）→ clean 后复跑一次再定论。环境没有 `bash` 时走 questions 通道，不要改用别的拼法硬跑。

## 可疑裁决复核（主控的唯一仲裁手段）

出现下列任一情形：

- 裁决与回执自查直接矛盾，且 ❌ 证据指向**环境噪音**（缓存、锁竞争、端口占用）而非产出物本身；
- 同轮多份裁决对同一全局事实（如"项目能否编译通过"）结论相反；
- 裁决缺失或格式残缺。

处理：重派一名**全新** Verifier 复核，验证简报「附加约束」注明"本次为复核，构建/测试前先执行 clean"，以复核结论为准，**不消耗任务重试次数**。主控在任何情况下不得以亲自读产出物、亲自跑命令的方式仲裁——实测一次亲自仲裁烧掉的预算约等于三个任务的正常调度，且破坏铁律。复核结论仍可疑 → 升级用户（questions 通道）。

## 全局决策记录 `loop/decisions.md`

跨任务传递信息的补充通道，解决**传递性依赖的信息丢失**（直接依赖注入只覆盖一跳，链条更长的决策会丢）。规则：

- 任务落地后，主控把回执「关键决策」逐条追加为 `decision` 事件（照抄条目文本与其 `[scope]` 前缀，每条一个事件）；decisions.md 是事件流的投影，每轮重算。
- Worker 按简报阅读清单中列出的 scope 自行匹配读取（`global` + 主控筛出的相关 scope），**不全文注入**——决策索引随任务数线性增长，而每个 Worker 只需要与自己领域相关的切片。
- Verifier 禁读 decisions.md（评判独立性红线，见验证简报禁读清单）。

## 人机通道：`loop/questions/` 与 `loop/inbox/`

两条纯文件通道，让人类无需守在场也能参与循环。

### 提问（主控 → 人类）：`loop/questions/<task-id>.md`

主控遇到需要人类决策的情形（缺凭据/权限、git 身份未配置导致封箱提交失败、清单内在矛盾、Worker 报告需要破坏性操作、任务超出单次上下文、⚠️ 条目过半、复核仍可疑、环境没有 bash 无法跑 checks），写出问题文件并追加 `task_waiting` 事件：

```markdown
# 问题: <task-id>
- 时间: <ISO 时间>

## 背景
<2-5 行: 任务是什么、卡在哪里、为什么需要人类决定>

## 问题
<一个具体、可回答的问题; 需要选择时列出选项>

## 答案
<人类: 在此节下方填写答案, 保存即可>
```

主控每轮开头检查所有问题文件：「## 答案」节下方出现非空内容 → 追加 `task_reset`（reason 注明"已回答"），任务回到 `pending`，重派时把该问题文件列入简报阅读清单。问题未答期间，其余不受影响的任务照常调度——**提问只挂起一个任务，不停摆整个循环**。

### 指令（人类 → 主控）：`loop/inbox/<任意名>.md`

人类随时可写，无需等循环暂停。格式自由，一行指令加必要说明，例如：

- `重置 T5` → 主控追加 `task_reset`（blocked/failed 任务解救）
- `终止循环` / `暂停调度` → 主控落盘后将投影状态置为 waiting-human 并停止
- `把 max_ticks 调整为 40` → 追加 `config`（`key` 为 `max_ticks`，`source` 为该 inbox 文件）。这不是元循环白名单项，只有人类指令可以改；重放规则见 event-spec
- 其他自然语言指令 → 主控按协议精神执行，无法执行的记入备忘并说明

主控每轮开头处理全部 inbox 文件，处理后把文件移入 `loop/inbox/done/`（留痕），执行情况以 `note` 或相应状态事件落盘。

## 重试与升级规则

- 每个任务最多重试 **2 次**（共 3 次尝试；上限可由元循环在 `protocol/meta-spec.md` 白名单内调整，当前值见 state.md 运行配置）。消耗规则按 event-spec 失败类别词表：`honest` 首次不计（诚实自查省掉一次验证调用，不应在机制上受罚），`transient`/`conflict`/`environment` 均不计——只有确定性失败（`acceptance`/`constraint`/`report_missing` 与第二次起的 `honest`）消耗重试。可疑裁决复核同样不消耗。
- 重试前主控必须写出「上次失败的反思」并放入新简报：失败在哪条标准、推测原因（以裁决「修复建议」为主要依据）、这次要怎么改。禁止无反思的原样重发。
- 重试前先归档上次尝试的简报/回执/裁决（见文首归档规则），旧工作区按事务规则丢弃。
- 重试仍失败 → 追加 `task_blocked`，继续调度其他不受影响的任务；所有可做任务做完后，向用户汇总全部 blocked 任务及其失败史（依据归档的历次回执与裁决），投影状态置 waiting-human，请求人工介入。人类解救方式见「人机通道」。
- **立即升级**（走 questions 通道 + `task_waiting`，不消耗重试次数）的情形：任务需要清单未提供的凭据/权限、封箱提交因 git 身份或权限失败、发现清单内在矛盾、Worker 报告需要破坏性操作、Worker 报告任务超出单次上下文可完成范围（建议用户拆分任务，而非让 Worker 硬撑）、环境没有 bash 无法执行 checks。
