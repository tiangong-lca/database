---
title: Supabase Branching
docType: guide
scope: repo
status: active
authoritative: false
owner: database-engine
language: zh-CN
whenToUse:
  - 当你需要确认 Supabase 分支绑定、preview 行为或持久化 dev 自动化时
  - 当你需要用中文查看本仓的 branch-specific 数据库工作流时
whenToUpdate:
  - 当分支绑定、Vault secret 规则或持久化 dev 部署路径变化时
  - 当这里的分支运维说明与 repo contract 或验证指南不一致时
checkPaths:
  - docs/agents/supabase-branching_CN.md
  - AGENTS.md
  - .docpact/config.yaml
  - supabase/config.toml
  - supabase/templates/**
  - scripts/check_auth_email_templates.py
  - .github/workflows/supabase-dev.yml
  - .env.supabase.dev.local.example
  - .env.supabase.main.local.example
lastReviewedAt: 2026-09-26
lastReviewedCommit: 5b6a2508dcfbe7c602f8cce848d1430a9796ddfa
lastReviewedNote: "Reviewed Database #723 main-hotfix narrow Portal readers, coverage cutover, real-writer/equivalence/concurrency proof and isolated fixture disposition. Public DTOs, writer/ACL contracts, 8-second budgets and main-to-dev/root delivery boundaries remain; local schema snapshots require exact reconstruction and deterministic regeneration."
related:
  - ../../AGENTS.md
  - ../../.docpact/config.yaml
  - ./repo-validation.md
  - ./repo-architecture.md
  - ./supabase-branching.md
---

# Supabase Branching

`database-engine` 是 TianGong LCA workspace 中唯一的 Supabase 真相源仓库。

本仓库负责：

- `supabase/config.toml`
- `supabase/migrations/*.sql`
- `supabase/seed.sql`
- `supabase/seeds/*`
- `supabase/tests/*.sql`
- `supabase/templates/*.html`
- `.env.supabase.dev.local.example`
- `.env.supabase.main.local.example`
- `.github/workflows/supabase-dev.yml`
- 数据库交付相关的 branching 与运维文档

本仓库**不**负责：

- 前端运行时 `.env` / `.env.development` 之类的环境文件
- 应用侧 Supabase client 代码
- Edge Function 运行时代码

这些职责保留在 `tiangong-lca-next`、`tiangong-lca-edge-functions` 等消费者仓库中。

## 分支契约

- Git `main` -> 生产基线，由 Supabase GitHub integration 自动迁移
- Git `dev` -> 持久化 Supabase `dev` 分支，由 `.github/workflows/supabase-dev.yml` 迁移并验证
- PR / feature 分支 -> 由 Supabase GitHub integration 自动创建的 preview branch

规则：

- GitHub default branch 继续保持 `main`，这是平台层例外。
- 日常 trunk 是 Git `dev`。
- routine feature / fix 分支从 `dev` 拉出，并向 `dev` 发起 PR。
- `dev -> main` 是正式晋升路径。
- 不要只根据 GitHub default-branch UI 推断实际工作 trunk。

如果 review 修改了 PR Preview 已记录的 migration，必须增加一条更晚的 migration，
把最终权威 schema/function 前向应用到该现有 Preview。仍须保留并运行真实的 populated
canonical-base-to-head upgrade；追加的 Preview repair 本身不能证明首次生产升级安全。

## 仓库契约

- 在 Git 中只维护一套共享的 `supabase/` 目录。
- 把 `supabase/migrations/` 中已提交的文件视为 production、`dev` 和 preview 分支共同遵循的 schema 真相源。
- 分支差异放在 `supabase/config.toml` 的 `[remotes.<branch>]` 中。
- 不要为不同 Git 分支复制多套 `supabase/` 目录。
- pull-request-only Preview 运行态 job 必须与部署隔离。fork PR 在授权前跳过。同仓 PR 先 checkout 准确 head 并验证事件 base/head commit，只比较可部署 Preview 输入：`supabase/config.toml`、`supabase/migrations/`、`supabase/seed.sql`、`supabase/seeds/` 与 `supabase/functions/`。生成 workspace、tests、Auth templates 与仓库文档不是部署输入。该集合无 diff 时，job 无需 secret、branch 解析或 hosted mutation 即成功，并接受官方 App 的 `skipped`。任一可部署输入变化仍要求完整官方 check、BranchResponse、PostgREST、public key、Hybrid 与 sitemap 证据，缺少 authority 时 fail closed。
- 把 `.github/workflows/supabase-dev.yml` 作为持久化 `dev` 的唯一 migration 部署者；它可以执行 `supabase link`、准确一次 `supabase db push --include-all`，以及一次仅包含 `db_schema`、`db_extra_search_path`、`max_rows` 的 Management API PATCH，让运行中的 PostgREST 与 checked-in 合同一致；但不得部署/删除 Edge Functions、执行 `supabase config push` 或修改其他项目设置。
- 独立的 ARM64 `scheduler-profile` 作业只重建本地数据库，运行两组完整的合成性能样本并在两组之间重置。x64 `local-contract` 继续运行功能和安全测试；持久化 Dev 部署须等待两个作业。性能作业没有托管凭据或部署权限。
- 数据库 workflow 成功后，通过 `tiangong-lca-edge-functions` 部署并验证持久化 Dev 所需的 Functions。Function 源码、函数选择、部署命令和运行时验证仍由 Edge 仓负责。
- 不要为 Git `main` 增加 checked-in 的 GitHub Actions 生产部署流程；生产项目由绑定到本仓的 Supabase GitHub integration 自动迁移。
- 不要先手改远端数据库再回头补 migration。

### Edge Function 部署

- 本仓不包含 `supabase/functions/` 运行时源码，也不部署 Functions。
- 持久化 Dev 数据库 workflow 成功后，从 `tiangong-lca-edge-functions` 部署目标 Dev Functions，并执行该仓当前的验证流程。
- 函数清单、部署命令、鉴权设置和运行时探测统一保留在 Edge 仓，不在本文重复维护。

## 需要维护的文件

- `supabase/config.toml`：共享基线加 `[remotes.dev]`
- `.github/workflows/supabase-dev.yml`：重建本地合同、不部署 schema 地修复并验证准确的 PR Preview 运行态、把已提交 migration 部署到持久化 `dev`，并验证准确的托管结果
- `supabase/migrations/*.sql`：已提交的 migration 历史
- `supabase/seed.sql`：共享 seed 数据
- `supabase/seeds/dev.sql`：可选的持久化 dev 专属 seed 数据
- `supabase/tests/*.sql`：数据库断言与安全检查
- `supabase/templates/recovery.html`：密码恢复邮件正文真相源
- `.env.supabase.dev.local.example`：持久化 `dev` 分支绑定模板
- `.env.supabase.main.local.example`：`main` 分支绑定模板
- `docs/agents/supabase-branching.md`：英文 branching 文档
- `docs/agents/supabase-branching_CN.md`：中文 branching 文档

消费者仓的前端 env 文件不会放在这里维护。

## 运维环境文件

仓库根目录需要维护以下分支绑定模板：

- `.env.supabase.dev.local.example`
- `.env.supabase.main.local.example`

使用规则：

- 复制为 `.env.supabase.dev.local` 或 `.env.supabase.main.local` 后再填写本地真实密钥。
- 真实 `.local` 文件禁止提交。
- 这组文件用于需要 `SUPABASE_PROJECT_REF` 或 `SUPABASE_DB_URL` 的运维动作，对应持久化 `dev` 与 `main` 分支。
- 前端 `.env` / `.env.development` 仍然归 `tiangong-lca-next` 等消费者仓维护。

## GitHub integration 与密钥

生产项目的 Supabase GitHub integration 应绑定到：

- repository: `tiangong-lca/database`
- relative path: `supabase`

当 Git `main` 前进时，该 integration 会自动把已提交的 migration 应用到生产项目。
仓库中没有针对 `main` 的 checked-in GitHub Actions workflow，并不表示生产迁移只能手动执行。

`.github/workflows/supabase-dev.yml` 依赖以下仓库配置：

- variable `SUPABASE_MAIN_PROJECT_ID`，值为 Supabase Branching 使用的生产 parent project ref
- variable `SUPABASE_DEV_PROJECT_ID`
- secret `SUPABASE_ACCESS_TOKEN`
- secret `SUPABASE_DEV_DB_PASSWORD`

Preview job 只把 `SUPABASE_MAIN_PROJECT_ID` 用作 Branching parent，只把
`SUPABASE_DEV_PROJECT_ID` 用作排除保护，并仅在 branch/config/public-key Management
步骤使用 `SUPABASE_ACCESS_TOKEN`。`SUPABASE_DEV_DB_PASSWORD` 继续只提供给
push-only 的持久化 Dev job。

## PR 到 Supabase migration 路径

已提交的 migration 文件不会因为文件存在就影响远端数据库，只有下面这些部署路径运行后才会生效。

常规 PR 路径：

1. feature 分支包含新的 `supabase/migrations/` 文件。
2. PR 目标分支是 Git `dev`。
3. 当 PR 修改可部署 config、migration、seed 或 Function 输入时，Supabase GitHub integration 创建或更新 preview branch。
4. 该 preview 只用于 PR 级验证，绝不是持久化 `dev`。如果事件 base-to-head 的
   可部署输入 diff 精确为空，PR 不需要 preview branch，仓库 job 在 allowlist 分类后成功结束。
5. 当前 PR head 上准确的 `Supabase Preview` check 成功后，同仓 Preview 运行态 job
   解析该准确 Git 分支，只应用并回读 `db_schema=public,api,graphql_public`、
   `db_extra_search_path=public,api,extensions` 和 `max_rows=1000`，随后仅用
   publishable 或 legacy anon `apikey`（不带 `Authorization`/`Cookie`）验证显式
   `api` Portal Hybrid 严格响应、伪造参数不透明性、被拒绝的 `private`/`public`
   profile，以及固定 sitemap manifest/shard 合同。Hybrid 与 sitemap readiness
   各自在一个 300 秒总期限内结束；Hybrid 失败后 sitemap 仍独立运行，因此 hosted
   证据不会相互耦合。
6. 合并后，`.github/workflows/supabase-dev.yml` 先完成本地空库重建；本地合同通过后，绑定配置的持久化 Dev 项目并执行 `supabase db push --include-all`。
7. workflow 从当前 checkout 的 migration 目录推导期望 head，再等待 service-only readback 报告该准确 head；workflow 中不手工固定 migration head。
8. workflow 在第一次托管 RPC 探测前，通过一次定向 Management API PATCH
   应用且只应用 `db_schema=public,api,graphql_public`、
   `db_extra_search_path=public,api,extensions` 与 `max_rows=1000`；随后回读
   这三个值并验证托管 Data API 边界，其余检查均为只读。
9. 数据库 workflow 成功后，通过 `tiangong-lca-edge-functions` 部署并验证目标 Dev Functions。

`--include-all` 表示所有尚未出现在远端 migration history 中的已提交 migration
都可以被应用。受治理的 `main -> dev` 回合并可能带入时间戳早于 `dev` 已记录新
migration 的提交，因此必须使用该参数；已经存在于远端 history 中的 migration
仍会被跳过。

### Pull-request Preview 运行态验证

- 该 job 只处理同仓库的 `pull_request` 事件并依赖本地合同；fork PR 在获得授权前跳过。
  同仓 PR 在任何 secret 或 Management API step 前，先证明事件 base/head commit 与
  可部署输入 allowlist 准确可用。
- 同仓 PR 缺少 `SUPABASE_ACCESS_TOKEN`、`SUPABASE_MAIN_PROJECT_ID` 或 `SUPABASE_DEV_PROJECT_ID` 任一项时 fail closed，不猜测项目 ref，也不使用持久化 Dev 兜底。
- 只有可部署输入 allowlist 精确无变化时才不要求 Preview check。任一 allowlist diff 都必须使用官方 Supabase App id `330661`、slug/owner `supabase` 的成功 check，从准确 dashboard `details_url` 捕获 ref，解析唯一 disposable BranchResponse，并要求 ref 相等且不同于 main/Dev。Preview 必需时，失败、取消、跳过、stale、neutral、超时、歧义或非官方 check 都 fail closed。
- 解析出的 ref 必须同时不同于 main parent 与持久化 Dev；job 不执行 `supabase link`、`db push`、Functions 命令、广义 `config push`、seed 或 migration。
- Management API 修改准确为对该 disposable ref 的一次 PATCH，且只含 checked-in PostgREST schema、search path 与 row limit；传输探测前必须再通过独立 GET 回读三项。
- 独立 key step 只做一次不带 `reveal` 的 Management API GET，并使用原始 `disabled` 字段；只接受非空、形态正确且启用的 publishable key，缺少时才回退到形态正确且启用的 legacy `anon`。选择出的公共 key 先 mask/export，随后清除 PAT 与原始 JSON；后续 REST step 不含 PAT/service credential，只带 `apikey`，绝不带 `Authorization` 或 `Cookie`。
- Hybrid 与 sitemap readiness 各自使用一个 300 秒 wall-clock deadline。公共 key
  step 成功后，即使 Hybrid 失败，sitemap step 仍独立运行；任一必需边界失败时，
  整体 job 仍然失败。
- 匿名显式 `api` probe 失败时，job 只能输出 HTTP status 与通过严格响应形态校验的 PostgREST/SQLSTATE code；不得输出原始 response body、`message`、`details`、`hint`、请求 payload 或公共 key。形态异常时统一记录为 `unclassified`。

### Issue #474 一次性持久化 Dev 账本修复

持久化 Dev 曾把 comment-draft migration 记录为 `20260810170000`，而生产环境
用同一版本号记录了内容不同的热修复。收敛后的 Git 历史保留生产文件
`20260810170000`，把内容逐字节不变的 Dev migration 重编号为
`20260810170001`，并在 `20260812090000` 增加 cutover 后的 private-schema 修复。

第一次把该历史部署到持久化 Dev 之前，运维人员必须先绑定 Dev 项目，确认远端
`20260810170000` 当前确实是旧 comment-draft migration，然后只修复 migration
history 账本：

```bash
supabase migration repair 20260810170000 --status reverted
supabase migration repair 20260810170001 --status applied
supabase migration list
supabase db push --include-all
```

`reverted` 只删除旧版本记录，不会回滚已经执行的 SQL；`applied` 只登记重编号后、
内容完全相同的 migration，不会再次执行。最后一次 push 会应用生产热修复（在
private-schema cutover 后按设计为空操作）以及新的 private-schema 收敛 migration。
不要对生产环境运行这组命令：生产的 `20260810170000` 已经是规范热修复记录。
正常持久化 Dev workflow 放行前，必须把修复前后的 migration list 与托管验证证据
记录到 Issue #474 或交付 PR。

Promote 路径：

1. `dev -> main` promote PR 合并到 Git `main`。
2. 生产项目的 Supabase GitHub integration 会读取 Git `main` 中已提交的 `supabase/` 目录。
3. 尚未应用的已提交 migrations 会自动应用到生产项目。
4. 如果 `supabase/config.toml` 有变化，运维人员应在 migration 已应用后执行
   `supabase config push --project-ref <production-project-ref> --yes`，并通过
   Management API 校验 PostgREST 配置。
5. 运维人员在 promote merge 后验证生产 migration 状态和应用行为。

对于 schema 边界的一次性切换，Preview 与持久化 `dev` 验证必须覆盖：无 profile
时通过托管端默认 `public` 访问核心实体、显式 `public` 实体访问、显式 `api` RPC、
拒绝 `private`，以及旧 `public` RPC 路由不存在。Data API 消费者必须为实体选择
`public`、为 RPC 选择 `api`，不能依赖本地 CLI 的 schema 排序。生产迁移可以使用
短时维护窗口，但所有消费者修改必须先在持久化 `dev` 完成验证，再执行
`dev -> main` promote。

本仓目前没有 checked-in 的 `workflow_dispatch` 生产 Supabase 部署流程。这是有意设计：
Git `main` 由 Supabase GitHub integration 处理。运维人员仍可在本地执行
`supabase link` 和 `supabase db push --include-all`，但这只能作为明确的兜底或恢复路径，
并且必须在验证记录或事故记录中说明。

## Auth 邮件模板契约

`supabase/templates/recovery.html` 是密码恢复邮件正文的真相源，
`supabase/config.toml` 中的 `[auth.email.template.recovery]` 负责主题和本地 CLI
绑定。交付前运行：

```bash
python3 scripts/check_auth_email_templates.py
python3 scripts/test_check_auth_email_templates.py
```

按钮和可见、可复制的备用链接都必须直接使用 Supabase 提供的完整
`{{ .ConfirmationURL }}`。禁止用 `.TokenHash` 手工拼接验证 URL，也禁止把恢复链接
写成 `type=magiclink`。

提交该文件、应用 migration 或合并 `main`，都不能单独证明已有托管项目中的 Auth
邮件模板已经变化。代码 PR 通过评审后，获得明确授权的运维人员必须进入准确目标项目的
**Authentication -> Email Templates -> Reset Password**，原样复制仓库内的主题与 HTML，
不得修改 URL 表达式，然后发送一封真实恢复邮件。必须通过 Next 应用分别验证按钮和复制
链接，并在交付 Issue 或 PR 中记录目标环境、时间与通过/失败回读。不得把 access token、
渲染后的恢复 URL 或原始邮件内容写入日志或 GitHub 记录。

## Vault secret 契约

数据库侧函数或 trigger 调用 Edge Function 时，必须读取 branch-specific Vault secret。

当前标准名称：

- `project_url`
- `project_secret_key`
- `project_x_key` 仅用于兼容旧的 `generate_flow_embedding()` 路径

规则：

- 不要把 branch URL 或 service key 硬编码进 SQL、migration 或导出的 baseline 文件。
- 这些值是 branch-specific 的。`main`、持久化 `dev`，以及任何需要执行 webhook 的 preview branch 都要各自提供所需 secret。
- 如果 branch 被重建或重新关联，测试 webhook 之前要重新核对 Vault entries。

## 默认工作流

### 常规 schema 变更

1. 同步本地 Git `dev`。
2. 从 `dev` 创建 feature 分支。
3. 启动本地 Supabase。
4. 在本地完成 schema 变更。
5. 用 `supabase migration new <name>` 或 `supabase db diff -f <name>` 生成 migration。
6. 用 `supabase db reset` 和相关 SQL 测试完成验证。
7. 把 migration、seed、测试和 config 一起提交。
8. 向 Git `dev` 发起 PR。
9. 让 Supabase 为该 PR 自动创建或更新 preview branch。
10. 合并后，验证持久化远端 `dev` 数据库，再通过 `tiangong-lca-edge-functions` 部署并验证目标 Dev Functions。
11. 准备发布时，再把 `dev` 晋升到 `main`。
12. 验证生产 Supabase 项目已经由 Supabase GitHub integration 自动完成迁移。

### 持久化 `dev` 分支部署

- 对 Git `dev` 的 push 由 `.github/workflows/supabase-dev.yml` 部署。
- workflow 先在本地重建并验证完整 migration history；Hosted job 依赖该结果，
  随后绑定配置的 Dev 项目，并准确执行一次 `supabase db push --include-all`。
- 部署后先应用准确的三字段 PostgREST 运行时 PATCH，再从当前 checkout 推导
  期望 head；exact-head readback、Management API 回读或 REST profile 探测任一
  不符合合同时都失败。
- workflow 只负责数据库 migration 与这一次窄范围 PostgREST 运行时刷新，不得执行
  `supabase functions deploy`、`supabase functions delete`、`supabase config push`
  或其他 Management API 修改。
- 数据库 workflow 成功后，使用 Edge 仓当前的 Dev 部署与验证流程；不要在本仓复制其函数清单或部署参数。

### 生产 `main` 部署

- 对 Git `main` 的 push 由生产项目的 Supabase GitHub integration 处理。
- 该 integration 监听 repository `tiangong-lca/database`，relative path 为 `supabase`。
- 当 `main` 前进时，已提交且尚未应用的 migrations 会自动应用到生产项目。
- 不假定项目配置会随 migration 自动同步；`supabase/config.toml` 变化时，必须
  显式推送到生产项目并验证托管 PostgREST 设置。
- 不要把缺少 checked-in 的 `main` GitHub Actions workflow 理解为需要手动部署。
- 本地 `supabase db push` 仅作为明确的兜底或恢复路径使用，并需要记录该动作。

### Hotfix 流程

1. 从 Git `main` 拉分支。
2. 修复问题。
3. 合并回 `main`。
4. 再把 `main` 回合并到 `dev`。
5. 保持两条长期分支上的 migration 历史一致。

## 消费者仓边界

以下变更应在 `database-engine` 完成：

- schema、policy、SQL function、trigger、seed、config
- preview / persistent branch 行为
- 数据库侧测试与 migration 恢复

以下内容保留在消费者仓完成：

- 前端 env 选择与应用侧 Supabase client
- Edge Function 运行时代码
- 应用对 `dev`、preview、`main` 的联调验证

如果一个需求同时改数据库和应用行为，数据库部分仍然从这里开始。

## 恢复规则

- 如果本地和远端 migration history 不一致，先用 `supabase migration list` 查清楚再继续。
- `supabase db pull` 只用于为既有远端 schema 建 baseline，或把远端独有的 drift 回收到 Git。
- 如果某个 branch 进入 `MIGRATIONS_FAILED`，优先在 Git 中修 migration 并重建失败分支，而不是手工硬改远端状态。
- 如果远端 history 元数据本身错了，再有意识地执行 `supabase migration repair`，然后重新核对结果。

## 本地命令

在本仓内统一使用 Supabase CLI。

- `supabase start`
- `supabase db diff -f <name>`
- `supabase migration new <name>`
- `supabase db reset`
- `supabase migration list`
- `supabase link --project-ref <ref>`
- `supabase db push`
