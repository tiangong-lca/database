---
title: Scripts
docType: guide
scope: repo
status: active
authoritative: false
owner: database-engine
language: zh-CN
whenToUse:
  - 当任务涉及 schema-workspace 辅助脚本时
  - 当你需要确认 workspace 刷新或 migration 生成的支持命令面时
whenToUpdate:
  - 当脚本入口、支持的 source path 形态或 workspace 刷新行为变化时
checkPaths:
  - scripts/README.zh-CN.md
  - scripts/**
  - supabase/workspace/**
  - docs/agents/repo-architecture.md
  - .githooks/pre-push
  - scripts/docpact
  - scripts/docpact-gate.sh
  - scripts/install-git-hooks.sh
lastReviewedAt: 2026-11-11
lastReviewedCommit: 16be0a5f2357a05c74f9d3211cba5ac723e2af18
lastReviewedNote: "Database #966 reviewed transition alias retirement and stable archive readback."
related:
  - ../AGENTS.md
  - ../.docpact/config.yaml
  - ../docs/agents/repo-architecture.md
  - ../docs/agents/repo-validation.md
  - README.md
---

# Scripts

这个目录包含用于远程 schema 导出、workspace 刷新、修改复制、migration 生成和受控数据迁移的命令行脚本。

`render_calculation_admission_proof.py upgrade|transactions --output <新SQL路径>`
将计算提交测试中引用的 fixture 和实际 migration 展开为单一文件，供容器内运行；
不连接数据库，拒绝覆盖已有输出。前序版本、隔离和重置要求由 validation guide 维护。

Database #785 的 `benchmark_advisor_invoker_paths.py` 与
`benchmark_advisor_navigation_indexes.py` 仅接收明确复用的 `workspace-1701` /
`supabase_db_database-engine-777-pg1711` 本地17.11栈及新的证据路径。两者把合成
fixture 保留在回滚事务内、交替比较前序/候选、记录自然计划并验证清理。Invoker
证明包含普通 schema 的 hostile canary 与真实 Alias 执行；Navigation 证明包含完整
JSON/cursor 及索引存储/写成本。这些本地资格不代表 hosted 性能。

`check_advisor_dispositions.py` 验证公开的逐对象 source contract；可选
`--snapshot <private-cli-advisor.json>` 只检查基线对应关系，不打印或复制实际运营
数值。逐项 source/release 决策与复审条件保存在
`supabase/tests/fixtures/20261006_advisor_dispositions.json`；实际部署与 hosted
资格状态以 Issue/PR receipts 为准。


`benchmark_portal_display_scope.py` 在 14 万条合成版本上，对比 #807 私有品牌
资格查询和有界统计与精确前序实现。它仅接受明确归属本任务的指定空本地栈、
`--samples`（1–5）和新 `--report` 路径，交替执行前序/候选并回滚全部 fixture
和 DDL。完整验证边界见 repo validation guide。

`benchmark_portal_lexical_keys.py` 与 `test_portal_lexical_upgrade.py` 只在明确归属
Database #925 的 `portal-query-925-pg1711` 本地栈验证。两者要求精确 `--base-ref`
和新的证据路径，须串行运行，并在规模测试和 writer 测试之间重置该栈。
完整证明边界由 validation guide 维护；本地结果不等同于线上恢复。

`--compare-validation` 使用本地 PG17 事务级函数统计验证完整 Search 调用中目录校验由两次变为一次，并覆盖筛选、排序和旧游标。`check_portal_read_failure_diagnostics.py --log <SQL测试日志>` 验证实际异常日志仅含封闭的粗粒度类别；CI 在诊断 SQL 测试之后运行该检查。原文、筛选值、游标、标识符和 SQL 不进入这些诊断字段。

`--compare-filtered-search` 增加大范围命中后的筛选请求，并用本地函数统计验证完整卡片事实只在结果页生成。升级 harness 的同名参数覆盖各类筛选、组合条件、排序和旧游标；扩展场景超时不能被先前的通过结果掩盖。
`--compare-filter-scope` 对比精确及大范围原生筛选下的搜索、Facet 和导航；基线还原旧的键读取器并移除新增封闭函数，候选再恢复准确权限。升级测试同时比较当前与历史全局作用域下的完整键集合；性能和隔离门槛见验证指南。


## 目录结构

长期维护的 helper 入口保留在本目录顶层。
一次性或按日期归档的数据修复 runner 放在：

- `scripts/data_migrations/<topic>_<yyyymm>/`

这类 runner 应在自己的 `README.md` 中保留 dry-run、apply 和 validate 示例。
本地迁移输出和审计 JSONL 文件应写入 `_artifacts/`，该目录已被 Git 忽略。

## 脚本列表

### Study P4 高级分析与 V5 报告

`prepare_study_advanced_project.py --destination <new-owned-dir>/study909` 仅创建
独立 PG17 配置和归属回执，固定 API56821/DB56822，不启动数据库。每次 CLI
操作必须显式传入 `--workdir <owned-study909>`，`SUPABASE_CLI` 指向固定的
2.117.0 底层可执行文件。`test_study_advanced_serialization.py` 核对 Worker
数值字串与配置身份；`test_study_advanced_upgrade.py` 仅在
`STUDY_ADVANCED_ALLOW_RESET=owned-study909` 下验证已填充 P3 升级和空库重建。
后续运行 `20261104_study_advanced_concurrency.py`、
`20261104_study_advanced_transport.py`，参数和顺序见英文 README 与 validation guide。

Schema 导出 helper 没有 workdir 参数，必须显式指定 `--environment local
--db-url <verified-study909-db-url> --schemas public api private util archive`；
裸 `--environment local` 会选择仓库项目，不是 study909。类型生成则显式使用
CLI 的 `--local --workdir <owned-study909>`。

并发/HTTP runner 保留明确合成数据，不重置或删除任何项目。先保存回执，再由
归属方明确重置用于生成 schema；最终仅释放 study909 的精确容器、卷和网络并
保存清理回执。SQL/JWT/合成签名不证明 GoTrue 同意、Edge、原生计算、实际
Storage 字节、真实密码学签发或行业科学资格。

### Study P3 审阅与指定接收人分享

`prepare_study_review_project.py --destination <new-owned-dir>/study906` 创建
独立 PG17 项目（API56621/DB56622）及归属回执，不启动或重置任何数据库。
`test_study_review_upgrade.py --workdir <owned-study906> --report <new-json>`
仅在 `STUDY_REVIEW_ALLOW_RESET=owned-study906` 下重置明确核验归属的项目，
验证已填充 P2 升级及完整空白迁移账本。后续运行
`supabase/tests/regression/20261103_study_review_concurrency.py` 和
`20261103_study_review_transport.py`，参数及顺序见英文 README 与 validation
guide。`SUPABASE_CLI` 必须指向项目固定的2.117.0底层可执行文件。

并发与 HTTP runner 保留合成数据，供归属方明确重置；不操作 P2保留的
study894 或共享 database-engine。SQL/JWT/并发证明不代替真实字节、签名、
GoTrue授权同意、Edge、安装版CLI或UI资格。保存回执后，只清理 study906
标签所标识的容器、卷和网络，并记录零残留证明。

### `test_search_request_identity_http.py`

仅在明确归属 Database #777 的本地隔离栈上执行真实 Auth/PostgREST
搜索身份回归。脚本核对 workdir 配置、project ID、loopback API 端口及
Kong 容器的一致性，验证匿名/外部成员拒绝、owner/team/public 读取及团队
成员资格撤销即时生效；最后登出并清理自己创建的合成身份与数据，确认零残留。
凭据及原始 HTTP 响应不会输出。
脚本禁用环境代理。若无法确认会话已撤销或身份归属，会保留相关测试身份并
返回未完成的清理回执，不会宣称零残留。

```bash
python3 scripts/test_search_request_identity_http.py \
  --workdir <absolute-isolated-workdir> --task-owned-local-stack \
  --supabase-cli <repository-pinned-supabase-executable>
```

允许的 project ID 为 `database-engine-advisor-777` 或 `database-engine-777-*`。
脚本不会重置数据库，也不接受远端项目或共享 `database-engine` 栈。
SQL request-identity 套件须单独运行。

### `test_release_manifest_drift.py`

对真实 forward release-manifest migration 与冻结的前序 migration 执行 23 项
最终回滚的 pgTAP 断言。覆盖两种已知向量、零写入重放、仅四行的 legacy 修复、
精确 identity／ACL 拒绝，以及客户端授权不变。只能明确选择本任务拥有的本地
Database container。

```bash
python3 scripts/test_release_manifest_drift.py --local-container <isolated-container>
```

### `test_oauth_release_migration_guard.py`

在客户端加载已提交 CLI release migration 的真实 DO block，执行七项 pgTAP 断言。
覆盖正常／幂等重放、缺失目标、重复语义 OID，以及总行数相同的缺失与重复组合。
fixture 修改、按需创建 pgTAP extension 和重放都在同一个最终回滚的事务内。

```bash
python3 scripts/test_oauth_release_migration_guard.py --local-container <isolated-container>
```

必须明确选择本任务拥有的本地 Database container；不支持 hosted DSN 或凭据参数。
脚本输出 TAP 结果，local-contract CI 在 OAuth release capability suite 后运行它。

### `configure_derivative_scheduler.py`

在 #703 migration 部署后，仅切换派生 cron 的每轮请求访问数（5／25）。
一分钟频率、active、owner 与其他字段必须保持完整快照一致；每轮合计最多
5 次外部转换仍由 coordinator 独立限制。该工具不安装 schema，也不修改业务数据。

使用仓库固定版本且已登录的 Supabase CLI。`SCHEDULER_PROJECT_REF` 是目标项目；
`SCHEDULER_COORDINATOR_SHA256`、`SCHEDULER_SELECTOR_SHA256` 来自独立验收的
干净 migration 构建，不能直接信任任意远端定义。`SCHEDULER_EVIDENCE` 指向新的
证据目录，父目录需已存在。

```bash
python3 scripts/configure_derivative_scheduler.py plan \
  --project-ref "$SCHEDULER_PROJECT_REF" --operation enable25 \
  --expected-coordinator-sha256 "$SCHEDULER_COORDINATOR_SHA256" \
  --expected-selector-sha256 "$SCHEDULER_SELECTOR_SHA256" \
  --out-dir "$SCHEDULER_EVIDENCE"
```

审核 `plan.json`、完整 before job 和 `review.sql`，把返回的 `approve_sha256`
作为 `SCHEDULER_PLAN_SHA256`。默认准确 migration head 是 `20260923053141`；
较新已验收部署需通过 `--expected-migration-version` 指定准确 head。

```bash
python3 scripts/configure_derivative_scheduler.py apply \
  --project-ref "$SCHEDULER_PROJECT_REF" \
  --plan "$SCHEDULER_EVIDENCE/plan.json" \
  --approve-sha256 "$SCHEDULER_PLAN_SHA256"
```

SQL 模板在 REPEATABLE READ 中使用 `cron.alter_job`，原子检查 source、project、
schema 与完整 before/after。并发管理员修改会拒绝或报 40001；绝不自动重试。
发送前以 create-only + fsync 保存 attempt；已有 attempt 或移到其他目录的 plan
均不能再次执行。凭据和原始错误正文不会打印，私有证据需保留到交付结束。
各命令均支持 `--supabase-cli /path/to/supabase`。

超时或结果不确定时，只用新的 readback 目录核验：

```bash
python3 scripts/configure_derivative_scheduler.py verify \
  --project-ref "$SCHEDULER_PROJECT_REF" \
  --plan "$SCHEDULER_EVIDENCE/plan.json" \
  --out-dir "$SCHEDULER_READBACK"
```

`desired`／`before`／`changed` 只证明当前状态，不证明不确定操作由谁提交。
不能靠重放或替换 plan 强制写入。回滚须先基于当前 25 次 job 生成新的 `rollback5`
plan，再审核并执行一次；恢复默认 `()` 命令（5 次访问，即使原来写的是 `(5)`），
且必须先于 schema/code 回退。准确 Preview 上先完成启用／回滚／再启用，生产
启用后使用新的原生测试账号请求，验收真实 worker 完成证明。

离线故障测试：`python3 scripts/test_configure_derivative_scheduler.py`。
专用本地并发及有数据升级测试在
`supabase/tests/regression/20260923_derivative_scheduler_*.py`；不能放宽其固定
隔离容器与黑洞 endpoint 守卫去操作共享或托管数据。保留证据后清理任务资源。

### `benchmark_hybrid_versions.mjs`

仅在明确命名的 Database #600 独立本地 Docker 数据库中，使用 rollback-only
合成数据比较 V1/V2 的 20 次耗时、前 10/20 项精确身份重合、历史版本覆盖和
Process 的 0、小集合、2,000、2,001、宽过滤、无过滤分段耗时，并记录宽过滤与
无过滤 V2 自然语义查询计划。Process 与 Flow 的 HNSW 计划都必须使用
`portal_public_executor`，并分别自然命中 `processes_embedding_ft_hnsw_idx` 和
`flows_embedding_ft_hnsw_idx`。没有远程 URL 或凭据参数；只输出计数、耗时和
索引名，不输出查询原文或向量。运行前后只重置该独立测试库。结果不代表真实
相关性或生产数据量发布证明。

`node scripts/benchmark_hybrid_versions.mjs --help`

### Raw 搜索及索引后续验证

Database #793 的工具仅允许明确归属的本地隔离环境，不接受托管数据库 URL 或共享本地栈。
解释结果前先阅读架构及验证文档；合成基准不能替代生产发布核验。

- `benchmark_raw_flow_hybrid.py`：创建并清理接近生产结构的 Flow 合成数据，比较完整 raw API、词法、向量及冻结候选后的融合阶段；首次调用与连续调用分开记录。候选 SQL、样本数和输出参数以 `--help` 为准。
- `benchmark_search_index_retirement.py --local-container supabase_db_database-engine-793 --output <新的私有JSON文件>`：对比主键前缀路径与大嵌套 JSON 的 GIN 读写成本；已有测试命名空间会被拒绝，测试对象必须回滚清理。
- `test_raw_search_request_bounds_http.py --workdir <隔离目录> --supabase-cli <准确CLI路径> --task-owned-local-stack`：使用真实 Auth 和 PostgREST 验证上限及正常边界，核实用户、会话和私有镜像清理。`--upgrade-authority-only` 在实际非超级用户迁移角色下验证临时 DDL 权限恢复。

`supabase/tests/upgrade/test_issue_793_search_index_retirement.py` 验证索引退役、已知终态重放、漂移拒绝，以及自身角色授权不存在、SET=false、SET=true 三种状态的精确恢复；每个场景回滚。目标和证据目录参数以其帮助为准。旧的 299 条迁移 Portal 基准仍属于历史版本验证，不代表当前 V2 退役验证。

### `benchmark_flow_lexical_payloads.py`

仅限明确命名的 Database #774 隔离容器。候选迁移和比较函数最终回滚；
合成数据先提交以便 VACUUM，再更新末尾 16% 数据以形成部分可见页。
证据文件记录实际可见页比例，不假定固定比例。先将该项目
重置到迁移 `20261002154951`。默认生成 134,608 条合成 Flow，在同一事务内
比较迁移前后的完整分页内容、排名、精确版本和总数，并记录自然执行计划。
脚本拒绝远程 URL，验证只按已选页精确读取 JSON 且减少临时块。`--output`
保存 JSON 和合成测试原始证据；完成后将隔离项目重置到当前迁移头。

`python3 scripts/benchmark_flow_lexical_payloads.py --help`

### `benchmark_next_hybrid_v2.mjs`

仅对显式命名的 Database #624 独立本地 Docker 数据库运行 rollback-only 的
Next Process/Flow 分段基准。它验证 0、1、2,000、2,001、宽过滤和无过滤的路由
分界、排序结果的稳定摘要、精确过滤与公开机构 team 索引、现有 PGroonga 索引，
以及符合条件的宽语义计划。该 runner 不接受数据库 URL 或凭据，并拒绝固定本地
命名合同之外的容器。本地合成耗时只作为路由证据，生产数据量发布门禁仍须在
持久化 Dev 完成。

`node scripts/benchmark_next_hybrid_v2.mjs --help`

### `check_auth_email_templates.py`

在不连接 Supabase 的情况下校验密码恢复邮件契约。它要求
`supabase/config.toml` 使用准确绑定和非空主题，并要求按钮与可见、可复制的链接都指向
同一个完整 `{{ .ConfirmationURL }}`；手工拼接 token hash 的 magic link 会被拒绝。

```bash
python3 scripts/check_auth_email_templates.py
python3 scripts/test_check_auth_email_templates.py
```

### `test_scope_closure_scanner_upgrade.sh`

现有 CI local-contract job 以 `SCOPE_CLOSURE_UPGRADE_ALLOW_RESET=isolated` 调用；
脚本还要求匹配的 GitHub 托管工作目录及本地 Unix Docker context，普通本地 checkout、
self-hosted runner 和被覆盖的 Docker 目标均在 reset 前拒绝。
脚本重置到固定 canonical R4 schema，复用 Scope Closure pgTAP 历史 fixture，在回滚事务内
执行两次真实 R5 singleton 迁移并验证记录保持，断言后才恢复当前迁移。CI 复用现有
local-contract job，不使用 hosted 凭据；这不验证原 R1 浏览器输入。
所需证据和关联套件见 `docs/agents/repo-validation.md`。

### `test_full_schema_cutover_upgrade.sh`

把本地数据库重建到全量 Schema 切换前的最后一个 migration，写入一条代表性业务数据，
快照关系与函数身份、触发器、RLS 策略、约束及精确行数，复现生产已先执行较晚
reuse-binding hotfix 的 ledger 顺序，运行 fail-closed bridge，再应用切换与契约收口
migration，验证对象和数据完整保留、能力清单、幂等索引及 Data Product 消费者 façade
已安装，并确认 API 函数不再向 PostgreSQL `PUBLIC` 角色开放执行权限。脚本还会应用
Issue #422 运行时 ACL 修复，并在有数据升级后校验 authenticated RLS helper 与 Edge
release façade 的精确授权，最后证明 bridge 在已完成切换的数据库上严格 no-op。

用法：

```bash
scripts/test_full_schema_cutover_upgrade.sh
```

此脚本仅用于本地验证，并会重置本地 Supabase 数据库。

### `test_search_text_array_upgrade.sh`

把本地数据库重建到 `20260810200000`，执行与生产相同的 `search_text`
migration，并证明七张表的 OID 与 heap relfilenode 都不变，同时代表性业务行完整保留。
随后脚本会再次重建迁移前状态，写入一个非空 scalar，证明 migration 会在修改任何列或
丢弃该值之前 fail closed。最后会把本地数据库完整重置到当前 checkout 的 migration head。

```bash
scripts/test_search_text_array_upgrade.sh
```

### `test_portal_projection_upgrade_recovery.sh`

在显式确认且隔离的本地 Supabase 项目中验证 Issue 531/532/539/543/551/563 Portal projection
上线。脚本使用真实并发连接覆盖有效更新、删除、状态失效、主键变更以及仅 embedding
更新竞态；主动制造 card/facet reconcile 锁超时与 cutover guard 失败；证明 facet
expand COMMIT/history 缺口、四分片幂等重试、同名 concurrent index 受控清理、Flow
eligibility guard 回滚、事务性 sitemap expand COMMIT-gap/reset、public cutover 与
forward repair 的回滚/重试、exact-version child 的 PK/FK/index、唯一 same-key upsert
trigger，以及所有旧 winner 对象均被移除。同一 identity 不同 version 的真实
insert/update/delete 必须全部提交，无 writer 侧 retry，并让 child rows 与已提交公开
facet version 集精确相等。脚本还证明已记录迁移重复执行不会重建八个索引，并拒绝
非 canonical 的 cursor numeric scale；SHA-pinned 的准确旧 Preview fixture 还必须
证明 populated 且已记录的 `134101`/`134102` 状态只应用 `134103` 即可收敛。
所需环境变量与恢复边界见
`docs/agents/portal-projection-migration-recovery.md`。正式证据还要求干净 HEAD、
Supabase CLI `2.109.1`，以及完整 299-file migration tree 的逐字相等和 aggregate
SHA-256。

### `test_portal_facet_projection_populated_upgrade.sh`

在同一类显式隔离的 Issue-531/532/539/543/551/563 项目中，对 126,246 条既有 parent card 逐字执行七个
Facet migration。每条 backfill statement 必须在 120 秒门下保留至少 2 倍余量，
每个完整 UUID-quarter 文件必须低于 120 秒；成功 reconcile fence 必须在 5 秒内
完成，并要求 key coverage、确定性抽样 facts 与 DTO 聚合计数精确一致。runner
随后在全部 126,246 行上按 60/15/15 秒证据预算（120/30/30 秒外层超时）计时三条
sitemap migration，并要求 facet/sitemap exact-version rows 双向相等、复合 PK/FK、
history-order index、唯一 same-key trigger、shard capacity 与两个 public RPC 精确
一致。runner 退出时总会把隔离项目重置到完整 HEAD。

### `run_portal_projection_benchmark.sh`

仅在显式确认的 Issue 531/532/539/543/551/563 隔离本地 Supabase 项目中运行代表性 Process/Flow
Search、Hybrid、Facets、写路径、fence、plan 与 ANN recall 基准。runner 会把完整
299-file migration tree 与仓库逐字比较，把结果写入操作员提供的新私有目录，并在运行前后
reset 隔离数据库，避免已回滚的 HNSW 页面持续累积。环境合同与 recovery runner
一致，另要求 `PORTAL_PROJECTION_BENCHMARK_OUTPUT_DIR`。

独立的 catalog-summary cardinality SQL 还会对动态选出的 classification 与 Flow
CAS example 各执行 20 个样本。它在临时 writer clone 上分别记录 combined
eligibility index 与 exact Flow CAS index 的 build time、bytes 和增量四次更新 p95；
该探针不会 drop 或 rebuild 真实 projection/index。`cas-pressure` profile 会让
10,000 个 current Flow card 共用一个 CAS，同时保留一个唯一 CAS，并要求受限选择器
保持 summary p95 <250 ms、已发布 CAS 只返回一条结果。同一代表性 fixture 还会捕获
forced-RLS exact-CAS 自然计划；除非 CAS 等值位于
`portal_catalog_search_flow_cas_v1_idx` 的 `Index Cond` 且没有 CAS JSON filter，否则失败。

完整 candidate benchmark 还会记录 20-sample
`process_single_character` / `flow_single_character` label；它们验证一个未转义
code point 的同步窄 character pre-limit，并要求 Search
p95 <2 秒。所有多 code point 与
已转义 literal 仍保留既有 PGroonga 模板。writer 证据包含唯一 child upsert
Trigger，populated/recovery runner 证明 child/parent parity。

`PORTAL_PROJECTION_BENCHMARK_PROFILE` 用于选择 fail-closed 命名 profile：

- `release` 使用代表性行数/向量数和 21,000 条旧 Flow 版本压力，记录自然
  raw-ANN 分支，直接验收两类完整规模 exact helper，并捕获生产一致的
  5,000-to-200 ANN 阶段；
- `sparse-zero` 使用代表性行数但不写 embedding；
- `sparse-199` 为每类数据只写 199 条 embedding；
- `diagnostic` 允许显式传入较小规模，不能作为发布证据；`auto` 会根据
  精确参数识别命名 profile。

所有命名 gate 都要求干净且精确的 HEAD，覆盖完整公开请求形态，保持
Search/Facets p95 <= 2 秒。Hybrid 必须在 20 秒有界 statement budget 内返回
严格公开 Schema；其时延继续记录并用于优化，但不再是发布门。正式 semantic
plan 必须含可解析的 shared-buffer 证据、低于 750,000 total / 250,000
read blocks，且没有
temp/disk spill。每次运行必须使用新的 mode-0700 输出目录。正式 lexical plan
使用与 Process/Flow pattern helper 完全一致的 leaf，并保持所有常规 planner
路径开启。代表性 Flow 基数必须自然命中其 PGroonga scan node；Process 基数较小，
因此记录自然成本计划而不强制某个索引，迁移期 catalog guard 负责证明其 PGroonga
索引，命名 timing 独立覆盖 Process 性能、排序和 cursor。两类 lexical probe 都
必须满足精确 needle fixture identity 且无 spill。
当 Process 行数不少于 10,000 时，每个 profile 还要求 exact-name/classification
探针自然命中 `portal_catalog_search_process_exact_rank_v1_gin`，记录索引字节，并把
新增表达式索引纳入既有 Process writer delta/ratio 门。
基准还会捕获匿名 Process/Flow 空 Facets 与过滤 Facets 计划，要求独立空路径在固定
32-MB 工作区内零 temp/disk spill，测量 parent-first facet reconcile fence，并把
facet child upsert 纳入现有
writer delta/ratio 门。
每个 profile 还会记录精确的 Flow embedding universe probe。sparse profile 必须
自然命中窄 partial eligibility B-tree，且不得扫描宽 Flow heap；release profile
记录全量 vector 的自然计划，不强制使用该索引。只有 release 必须命名两个 source
HNSW index；sparse source probe 可以选择 eligibility/empty-set plan，但仍必须提供
buffers、execution time 且没有 temp/disk spill。

所有命名 profile 都会构造 evidence-complete card context：每个 Process 都解析准确
公开 reference Flow 与真实 FlowProperty/UnitGroup functional-unit 支撑链，Process/Flow
还包含公开 source/database，Process 另包含 review/technology 字段。四个专用
Search-50/Hybrid-20 label 必须分别返回准确 50/20 个完整 item、20 个 timing sample，
并输出完整 wrapper `EXPLAIN (ANALYZE, BUFFERS)`。runner 会记录 temp-buffer 使用，
拒绝字段缺失、超过 750,000 total / 250,000 read shared blocks，以及超过既有 Search 2 秒 / Hybrid
6 秒门槛的结果。
证据文件还会单独保存空 query、`geography=cn` Flow Search-50 的完整计划，
因为它是代表性的过滤最坏路径；对应 timing label 也必须准确返回 50 个完整 item，
避免空结果或过窄结果让性能门假绿。

sitemap profile 的 126,246-row 单版本 fixture 保持最大 shard 为 2,066 个 identity，
记录的 shard-read p95 约为 11 ms。独立 history-density probe 将 2,048 个 identity
各扩展为 64 个 version，共 131,072 行；其自然 `DISTINCT ON` 计划必须通过精确
history-order index 走 index-only path，不得出现 `Sort` / `Incremental Sort`，不得
产生 temp spill，并须在 4 秒内完成。响应数量、字节与 timeout 仍有界，但扫描行数
会随保留 version 历史增长。

### `check_portal_projection_manifest.py`

同时验证已提交的 Portal digest：十一函数 stored-card 闭包、两函数窄 Facet
闭包，以及独立的 limit 后 context/decorator 闭包。它禁止后续 mutation 任一
闭包/控制函数，校验四个 Facet 分片、reconcile/cutover，要求 context migration
不新增 table/index/trigger，并保留 Flow eligibility index 的精确 catalog guard，
同时不改变两个 #531 digest。它还要求 Flow geography Search follow-up 只能是
单一 query-only kernel replacement，不得新增 table/index/trigger 或改写 writer；
runtime 在读取该 child projection 前还必须独立验证 Facet manifest。

检查器还冻结 Issue #563 的三步序列：dormant immutable rank helper、唯一 standalone
concurrent partial expression GIN，以及仅覆盖 multi-code-point、non-UUID、无过滤 Process
relevance 的原子 coordinator cutover。内部 writer 与 `postgres` 维护 ACL 必须准确，
不得改动公开 wrapper/Trigger/table，后续 migration 也不得静默修改该 helper closure。

它还会冻结 Issue #539 的 64-bucket exact-version child：table/PK、带
`ON UPDATE RESTRICT` / `ON DELETE CASCADE` 的 facet exact FK、history-order index，
以及唯一的 `AFTER INSERT OR UPDATE` same-key upsert trigger。公开 shard reader 必须
保留 index-ordered `DISTINCT ON (dataset_kind,id)` 选择、4,096-item / 2-MiB / 4 秒
边界和显式 history-density plan gate。`134103` forward repair 必须在一个事务内锁定
facet writer、建立并完整 backfill shadow child、替换 assertion/reader，并移除旧
winner table/helpers。shard cursor 字节必须等于精确期望对象的新编码，因此 JSONB
等价的 `1.0` / `64.0` numeric scale 也会被拒绝；旧 sitemap façade 仍逐字不变。

```bash
python3 scripts/check_portal_projection_manifest.py
```

### `check_portal_card_schema_parity.py`

除非 lexical Search 与 Hybrid candidate item 在各自版本化 `match` 之外具有
逐字一致且 exhaustive 的 card properties，并共同引用精确五字段
`PublicCardContext` 定义，否则立即失败。

```bash
python3 scripts/check_portal_card_schema_parity.py
```

### `resolve_migration_head.py`

从当前 checkout 的 `supabase/migrations` 目录输出最新的有效 migration 版本。
如果目录为空、SQL migration 文件名不合法，或存在重复的 14 位版本号，脚本会
fail closed，避免托管验证静默选择含糊的 head。

```bash
python scripts/resolve_migration_head.py
```

运行对应回归测试：

```bash
python scripts/test_resolve_migration_head.py
```

### `test_supabase_dev_workflow_contract.py`

12 组 event/base/repository 用例执行真实 Preview job 条件：日常 Dev PR、fork
与非 PR 事件不可进入；同仓 Main PR 保留原有分类与权限检查。

同一脚本在临时本地 Git 历史上执行 workflow 中真实的 push/Preview 分类 Bash，
覆盖五类可部署路径、仓库维护、混合删除/重命名、零值/未知 base、过期 checkout、
无祖先关系与 diff 错误。无凭据 local job 输出准确范围，持久 Dev job 必须同时
要求该输出及两项本地检查成功才可取得凭据；同仓依赖 bot 也不能绕过缺失的
Preview authority。测试还从明确归属临时 fixture 的本地 Git remote fetch，覆盖 A 可部署后跟 B 文档、
较新 C 先完成检查、迟到 A、后续 D 文档及 fetch/历史/diff 错误。独立 push run 保留检查，
串行部署队列保留等待者（上限 100）；部署锁内的准确当前 tree 证明必须控制每个
hosted step。完整 folded/plain 条件拒绝同行/续行 OR 绕过。
测试不启动 Supabase、不发外部网络请求，也不使用托管凭据。

除非 `.github/workflows/supabase-dev.yml` 保持两条相互隔离的托管路径，否则立即
失败。push-only 持久化 Dev job 必须绑定配置的 Dev 项目，准确执行一次
`supabase db push --include-all`，从 checkout 推导 migration head，并执行准确一次
三字段 PostgREST PATCH。pull-request-only Preview job 只允许以 Main 为目标的同仓 PR；日常 Dev PR 和
fork 在 job 边界跳过，不读取密钥、不执行云端操作，完整 local-contract/upgrade 与
ARM64 检查仍为必需。符合条件的 Main PR 先验证事件
base/head commit 和精确可部署 allowlist：config、migrations、根/附加 seed 与
Functions；workspace、tests、Auth templates 和文档不在其中。零 diff PR 输出
`required=false`，不执行 hosted Preview。准确的同仓 `dev -> main` promote 也会在
验证准确 commit/branch 后输出 `required=false`，复用 persistent-Dev 证明，且不接收 Preview authority、不执行 hosted mutation。其他符合条件的 Main PR
的任一 allowlist 变化仍要求 access token、main-parent ref 与 persistent-Dev ref；
随后必须把准确 head 上来自官方 Supabase App
的唯一成功 check，与 `branches list` 中按 Git branch、PR number、parent 匹配的唯一
non-default/non-persistent BranchResponse 绑定。两个 ref 必须相等且都不同于 main/Dev，
才能执行 Preview 的一次相同 PATCH 与回读。

合同还要求通过独立且不带 `reveal` 的 Management API key 读取，使用原始
`disabled` 状态与准确公共 key 形态筛选。只有已 mask 的启用 publishable 或 legacy
anon key 能进入下一 step；此前必须清除原始 JSON 与 PAT。匿名 Hybrid step 本身不得
包含 PAT、`Authorization`、`Cookie` 或 service credential。整个 workflow 唯一允许的
Management API 修改，是持久化 Dev 与 Preview 各一次 PostgREST PATCH；Functions
命令、广义 `config push`、手工固定 migration head 及其他修改仍全部拒绝。

合同还要求失败诊断只能输出 HTTP status 与通过响应形态校验的
PostgREST/SQLSTATE code；禁止打印原始 response body，形态异常或包含额外字段的
错误 envelope 必须统一记为 `unclassified`。

同一匿名凭据边界还会在最多 300 秒内轮询 sitemap manifest，验证准确 64 个不透明
descriptor，把其中一个 cursor 逐字传给 shard RPC，严格校验两个 exhaustive JSON
Schema，并要求伪造 cursor 只返回受限的 `22023` envelope。

```bash
python scripts/test_supabase_dev_workflow_contract.py
```

### `data_migrations/tidas_schema_202606/runner.py`

用于对远程数据库中的 TIDAS schema 2026-06 JSON 数据修复进行 plan、apply 和 validate。

用法：

```bash
python scripts/data_migrations/tidas_schema_202606/runner.py plan --environment dev --run-id tidas-schema-202606-dev --out _artifacts/tidas-schema-202606/dev-plan.jsonl --dry-run
```

完整命令面和安全说明见 `scripts/data_migrations/tidas_schema_202606/README.md`。

### `data_migrations/root_reference_review_v2_local.sh`

用于在 Root/Reference Review v2 切换前创建本地加密备份，并由操作员逐条迁移存量审核。

备份内容包括完整 custom-format dump、审核相关表 dump，以及七类业务表中受影响的数据行。备份目录必须位于 Git 工作树之外。只有操作员已独立验证恢复能力、确认第二份本地副本并生成 dry-run 清单后，`apply` 才会解锁。

用法：

```bash
DATABASE_URL='postgresql://...' \
REVIEW_BACKUP_PASSWORD_FILE='<本地密码文件的绝对路径>' \
scripts/data_migrations/root_reference_review_v2_local.sh backup \
  '/absolute/path/review-v2-backup'

DATABASE_URL='postgresql://...' \
scripts/data_migrations/root_reference_review_v2_local.sh dry-run \
  '/absolute/path/review-v2-backup'

DATABASE_URL='postgresql://...' \
scripts/data_migrations/root_reference_review_v2_local.sh verify \
  '/absolute/path/review-v2-backup'

DATABASE_URL='postgresql://...' \
scripts/data_migrations/root_reference_review_v2_local.sh apply \
  '/absolute/path/review-v2-backup'
```

操作员只能在真实完成恢复验证和第二份本地副本验证后，创建
`RESTORE_VERIFIED` 与 `SECOND_LOCAL_COPY_VERIFIED` 标记。不得把密码文件、
加密备份、标记文件或迁移清单提交到 Git。

### `export_remote_schema.py`

用于把目标远程数据库的 schema 导出到：

- `supabase/workspace/remote_schema.sql`

用法：

```bash
python scripts/export_remote_schema.py --environment dev
```

说明：

- 默认环境是 `dev`
- 默认 schema 列表是 `public`
- 可通过 `--schema-file` 覆盖输出路径
- 未传 `--db-url` 时，`--environment local` 使用 Supabase CLI 的 `db dump --local`；显式 `--db-url` 仍使用该 URL

### Study runtime 隔离证明（Database #894/#895）

`prepare_study_runtime_project.py --destination <new-owned-directory>/study894`
只复制独立 PG17 项目配置和 migration，使用 API56421/DB56422，移除 remote
binding 并记录 ownership；不启动或重置数据库，不修改 tracked config 或共享项目。
使用 Supabase2.117.0 启动该独占项目后，运行：

```sh
STUDY_RUNTIME_UPGRADE_ALLOW_RESET=isolated python3 -B scripts/test_study_runtime_upgrade.py \
  --workdir <owned-study894> --report <new-upgrade-json>
python3 -B supabase/tests/regression/20261103_study_runtime_concurrency.py \
  --report <new-concurrency-json>
```

前者从准确 W03 predecessor 验证既有 dataset/job/Study、13 项已审阅 routine
变更及周边 ACL/manifest/role 权限保留，再重建默认关闭能力的完整 candidate ledger；后者观察真实的两会话 advisory/row-lock 等待，保留合成 fixture 供资源 owner
准确重置。保留 receipts 后，通过 workspace 资源流程释放或明确接管该项目资源。
CLI 启动输出含本地生成密钥，须私有保存。完整边界见
[英文使用说明](README.md)及[Study runtime 合同](../docs/agents/lca-study-runtime-contract.md)；
这些 SQL 证明不代表真实 source export、编译、解算或 disclosure 已获资格。

### Study P2 分析与报告证明

`test_study_runtime_reporting_upgrade.py` 在显式保留的 study894/PG17 项目上
验证 `20261103110000` 的有数据升级与 P2 空库重建；运行前必须确认准确的所有权
JSON、无活动账号/客户端/任务，并设置 `STUDY_RUNTIME_UPGRADE_ALLOW_RESET=isolated`。
分析和报告并发脚本要求单独拥有、夹具命名空间为空的 `study904_*` 克隆库，通过真实
会话等待证明幂等、CAS、冻结和导出竞争；脚本本身不创建或删除资源。
SQL 数值、工件描述符及签名字串夹具仅证明数据库绑定，不证明真实字节或签名器。
保留回执后只清理准确拥有的克隆库；所有 P2 生产开关与默认客户端授权保持关闭。
完整参数、命令和资格边界见[英文使用说明](README.md)和
[验证指南](../docs/agents/repo-validation.md)。

### `build_schema_workspace.py`

用于刷新可读的 schema workspace，涉及：

- `supabase/workspace/remote_schema.sql`
- `supabase/workspace/global/`
- `supabase/workspace/schemas/`

用法：

```bash
python scripts/build_schema_workspace.py --environment dev \
  --schemas public api private util archive
```

如需按本地已应用 migration 精确重建：

```bash
python scripts/build_schema_workspace.py --environment local \
  --schemas public api private util archive
```

行为：

- 先导出最新远程 schema
- 规范化生成 SQL 视图的行尾空白，保证审查 diff 可重复
- 重建 `global/` 和 `schemas/`
- 保留 `supabase/workspace/README.md`
- 保留 `supabase/workspace/README.zh-CN.md`
- 保留 `supabase/workspace/changes/`

注意：

- `remote_schema.sql`、`global/` 和 `schemas/` 中的手工修改都不稳定
- 刷新时可能覆盖这些生成文件里尚未提交到 Git 的改动
- 如果你希望 `--git-changes` 只反映后续手工修改，应在同步远程数据库并刷新 workspace 之后，先把新的 `supabase/workspace/schemas` 提交到 Git，再开始编辑
- 远程 `dev` 仍是生成 schema 的权威目标。Schema 变更 PR 可以提交 exact-local 审查快照，但必须先通过空库 migration 重建、定向合同测试，并再次生成证明无漂移。合并后，数据库专用 Dev 部署必须到达准确 head、托管 catalog 检查必须通过，还要将 remote-Dev 刷新结果与审查快照比较；若有漂移，以后续提交收口。

### `build_database_types.py`

生成纳入版本控制的 TypeScript 数据合同，仅覆盖 Data API 暴露的 `public` 与 `api` 两个 schema。

```bash
python scripts/build_database_types.py --environment local
```

只有在刻意以已链接的 Supabase 项目为来源时才使用 `--environment linked`。CI 会从本地完整 migration 状态重新生成，并在 `supabase/workspace/database.types.ts` 漂移时失败。

该脚本只解析本仓库自身的 Supabase 目标，不接受 workdir 或数据库 URL 覆盖参数。若要从隔离的
任务 workdir 生成同一份合同，请使用等价 CLI 形式，并按生成器的 `rstrip()` 加末尾换行方式
机械安装其输出：

```bash
supabase gen types typescript --local --workdir <isolated-workdir> --schema public --schema api
```

### `build_portal_contract_types.py`

为每个 exhaustive Portal JSON Schema 生成一个纳入版本控制的 TypeScript module。
本仓没有 Node package manifest，因此脚本遵循既有 CI 依赖政策，通过 `npx`
调用精确固定的 `json-schema-to-typescript@15.0.4`。

```bash
python3 scripts/build_portal_contract_types.py
python3 scripts/build_portal_contract_types.py --check
```

普通生成会让 `contracts/portal/generated/*.d.ts` 与按名称排序的
`contracts/portal/*.schema.json` source set 同步。`--check` 只在临时目录渲染，
若 module 缺失、变化或多余则失败，且不修改 checkout；CI 使用该只读检查。

### `check_generated_workspace_legacy_tables.py`

检查生成的 schema workspace 是否仍在展示已退休的 public legacy job 表：

- `public.lca_jobs`
- `public.lca_package_jobs`
- `public.dataset_review_submit_jobs`

用法：

```bash
python scripts/check_generated_workspace_legacy_tables.py
```

当目标远程分支已经应用 `worker_jobs` cutover 和旧 job 表退休 migration 后，刷新 `supabase/workspace/**`，再运行这个检查。

### `copy_workspace_file_to_changes.py`

用于把生成目录中的文件复制到稳定的手工修改区：

- 从 `supabase/workspace/schemas/...`
- 到 `supabase/workspace/changes/...`

用法：

```bash
python scripts/copy_workspace_file_to_changes.py --source-path "supabase/workspace/schemas/public/tables/comments/table.sql"
```

```bash
python scripts/copy_workspace_file_to_changes.py --source-path "supabase/workspace/schemas/public/tables/comments"
```

```bash
python scripts/copy_workspace_file_to_changes.py --git-changes
```

行为：

- 保留相对路径
- 支持单个文件或目录
- `--git-changes` 会复制当前 Git 检测到的 `supabase/workspace/schemas` 下所有未提交文件
- 建议流程：先刷新 workspace，再将生成的 `supabase/workspace/schemas` 提交到 Git，然后再进行手工修改并使用 `--git-changes`

### `new_migration.py`

用于从受支持的 schema 对象文件生成 migration SQL，来源路径可以是：

- `supabase/model/schemas/...`
- `supabase/workspace/changes/...`

用法：

```bash
python scripts/new_migration.py --name "update policy roles update" --source-path "supabase/workspace/changes/public/functions/policy_roles_update/definition.sql"
```

输出：

- `supabase/migrations/<timestamp>_<slug>.sql`

当前支持的源文件路径形态：

- `functions/<name>/definition.sql`
- `views/<name>/definition.sql`
- `materialized_views/<name>/definition.sql`
- `tables/<table>/policies/<name>.sql`
- `tables/<table>/triggers/<name>.sql`

当前不支持：

- `table.sql`
- indexes
- sequences
- schema 级 SQL
- 其他生成出来的 workspace 文件

### `_db_workflow.py`

这是上面几个脚本共用的内部模块。

通常不作为日常命令行入口直接使用。

### `test_scope_closure_staged_write_set_v2_fixture.sh`

用于校验 Worker/数据库逐字共享的 staged write-set v2 fixture，包括
canonical JSON、descriptor-set SHA-256、bounded batch 上限、status 字段
不透明性、状态转换以及保留 one-shot 兼容窗口。

用法：

```bash
scripts/test_scope_closure_staged_write_set_v2_fixture.sh
```

这是只读的本地合同检查；不会刷新生成的 schema workspace，也不会连接远程数据库。

### Scope-closure provider 资格验证适配器

`run_scope_closure_database_qualification.sh` 和
`run_scope_closure_storage_qualification.sh` 生成 Worker provider aggregator
直接消费的 `lcia.scope-closure-provider-owned-result.v1` 记录。两个适配器都要求
Worker 提供 `--run-id`，把 `componentSha` 绑定到当前 database-engine commit，
只接受 loopback 或已明确加入许可清单的非生产目标 fingerprint，拒绝生产或不明确
目标，并固定输出 `productionMutation=false`。

数据库适配器对显式 `QUALIFICATION_DATABASE_URL` 执行 #308/#316
pgTAP 合同，并执行当前 private SQL service-role fixture：真实异步 register/seal、独立存储状态核对、PostgREST 隔离，以及延迟 Auth profile mirror 下的原子 setup。存储适配器使用显式 S3-compatible endpoint，并验证 bounded 生成
文件、有效及过期签名 HEAD/range 请求、multipart 边界、重试和精确 prefix GC。
结果中不会写入凭据、object locator、signed URL 或 payload 内容。

在精确 Worker commit `e5a7f769` 下，loopback 执行只构成协议、故障注入和
adapter 证据，不是最终 provider-specific 非生产资格验证。Worker #188 提供
已验证的非生产目标分类后，再使用同一组 owner adapter 运行最终验证；歧义目标
或生产目标仍必须 fail closed。

用法：

```bash
scripts/run_scope_closure_database_qualification.sh \
  --output <new-result-path> \
  --run-id <worker-supplied-uuid>

scripts/run_scope_closure_storage_qualification.sh \
  --output <new-result-path> \
  --run-id <same-worker-supplied-uuid>
```

必需环境变量：

- 两个适配器：`QUALIFICATION_NON_PRODUCTION_CONFIRMATION`
- 数据库：`QUALIFICATION_DATABASE_URL`、`QUALIFICATION_SUPABASE_URL`、
  `QUALIFICATION_SUPABASE_SERVICE_ROLE_KEY`
- 存储：`QUALIFICATION_DATABASE_URL`、`QUALIFICATION_S3_ENDPOINT`、
  `QUALIFICATION_S3_ACCESS_KEY_ID`、
  `QUALIFICATION_S3_SECRET_ACCESS_KEY`、`QUALIFICATION_S3_BUCKET`，以及可选的
  `QUALIFICATION_S3_REGION`
- 非 loopback 目标：`QUALIFICATION_VERIFIED_NON_PRODUCTION_FINGERPRINTS`，值为
  qualification coordinator 批准的、以逗号分隔的精确 SHA-256 目标身份；远程
  数据库和 provider endpoint 必须使用 TLS

不得改变记录 schema；用精确 Worker compatibility verifier 接收并合并两条记录：

```bash
scripts/verify_scope_closure_worker_aggregator.py \
  --worker-repo <worker-checkout-containing-e5a7f769> \
  <database-result> <storage-result>
```

离线控制流和安全回归命令：

```bash
python3 -m unittest scripts/test_scope_closure_provider_qualification.py
```

## Local Docpact Push Gate

The repository now includes a local pre-push docpact gate in `scripts/docpact-gate.sh`. The gate resolves the CLI through `scripts/docpact`. It is documentation-governance tooling and does not change database schema workspace behavior.

## Portal 导航工具

`python3 scripts/generate_portal_navigation_vocabulary.py --check` 只读验证离线词表及来源收据。只有经过审阅的来源变更才应省略 `--check` 并传入 `--seed-dir supabase/migrations` 重新生成。`--vendor --platform-root <path> --archive-locations <path>` 在核对平台精确提交后刷新来源副本；普通构建不联网刷新。来源收据、schema、类型与 seed migration 必须一起审阅。

后续层级变更必须通过 `data/portal-navigation-revisions.json`：生成器校验原始 seed 的固定字节，只生成由 CLI 新建的修订迁移。`python3 scripts/test_portal_navigation_revisions.py` 校验有来源依据的绑定与修订边界。`python3 scripts/test_portal_china_navigation_upgrade.py --local-container supabase_db_database-engine-662-isolated` 要求从修订前提交初始化、唯一命名且源表为空的本地项目；它创建 160 个合成公开版本，在已提交的旧成员关系上应用修订，核对精确计数及源数据不变，再清理夹具。该工具拒绝远端 Docker context 和非空源表；验证后应在这个可丢弃项目重放完整迁移历史。

`python3 scripts/benchmark_portal_summary_bounded.py --help` 说明本地、回滚式性能夹具。它拒绝远端 Docker context 和非空公开投影。读取规模测试不能替代生产延迟或源数据写入吞吐验证。

`python3 scripts/check_portal_json_schemas.py` 先注册关联文件，再以严格 Draft 2020-12 模式逐个编译 Portal schema。它沿用已固定的 AJV CLI 与格式插件版本，并将当前编译文件排除在引用注册列表外，避免依赖文件顺序和重复 ID；不会改写 schema。

### `benchmark_portal_catalog_bounded.py`

在同一批合成数据上，以 rollback-only 事务对比保留的旧迁移定义和候选
Portal 读函数。只接受本机 Docker socket、空投影和
`supabase_db_database-engine-723-*` 隔离容器；每个数据集含两个公开版本，
支持配置摘要宽度。直接填充投影只证明读取规模，真实写入维护由 SQL suite
另行验证。报告包含响应摘要、旧游标续页、实际切换门禁故障注入、耗时及
EXPLAIN ANALYZE/BUFFERS。名称排序仍需读取匹配名称，不能宣称常数工作量。

```bash
python3 scripts/benchmark_portal_catalog_bounded.py \
  --container supabase_db_database-engine-723-isolated \
  --process-datasets 9000 --flow-datasets 55000 --card-padding 2048 \
  --samples 5 --report /tmp/portal-catalog-serial.json
```

### `profile_portal_catalog_concurrency.py`

绑定成功串行报告中的精确候选与夹具。仅接受空的本机隔离库；串行测试后先
重建该任务隔离项目，避免回滚留下的物理页影响下一次夹具。为使独立连接
共享同一数据集，会提交合成夹具，然后依次对旧版和候选执行有界并发请求。
结束或失败时恢复候选读函数并输出处置记录。此工具与串行基准不同，保留
合成行供检查；留存结果后只 reset 该任务拥有的隔离项目，再按 workspace
资源生命周期释放容器、卷和网络。

```bash
python3 scripts/profile_portal_catalog_concurrency.py \
  --container supabase_db_database-engine-723-isolated \
  --reference-report /tmp/portal-catalog-serial.json \
  --concurrency 4 --requests 24 --report /tmp/portal-catalog-concurrent.json
```

两个入口都不接受 hosted URL，也不提高公共查询预算。语义与发布证明要求见
`docs/agents/repo-validation.md`。

## Portal 空查询对照

`benchmark_portal_empty_reads.py` 交替执行精确的前序和候选 Navigation/Facets，
比较完整响应并记录嵌套自然计划。它仅接受明确复用的 `workspace-1701`
PostgreSQL17.11 本地栈和空投影表。通过 `--help` 查看有界 fixture 参数；
报告、SQL 和计划日志必须使用新路径。合成 fixture 的所有变化回滚，
只作为读取证据；真实 writer/RLS 测试与托管性能仍需分别验证。

旧 Process V1 排名读取路径的退役在 `check_portal_projection_manifest.py` 中使用精确的 DROP-only 例外。运行 `python3 scripts/test_portal_rank_retirement_governance.py`，验证该例外不会放行共享/当前 helper、替换定义或其他迁移文件。

### Dataset display list benchmark

`python3 scripts/benchmark_dataset_display_list.py --local-container supabase_db_codex-display-801 --output <new-private-json>` accepts only the exact
task-owned local Unix Docker target and an empty seven-table source. The default
profile has 200,000 exact-version rows with unique TOAST-backed JSON, old/current
RPC response digests, seven request shapes and the current physical plan. All
fixtures and temporary trigger suppression roll back. Current queries must meet
the existing 15-second budget and hydrate only ten page names; output is private
and an existing output path is refused. These are synthetic local measurements.

展示迁移 #807 仅在 `check_portal_projection_manifest.py` 中放行该迁移的两个公共 sitemap 分发入口，旧 private 派生函数和后续迁移仍受冻结检查。`supabase/tests/upgrade/test_portal_display_upgrade.py` 在显式归属本任务的可丢弃数据库中验证旧函数体、owner、ACL 和配置保持不变。

### `benchmark_portal_display_sitemap.py`

Database #807 的本地 sitemap 对比工具，仅使用可回滚的合成测试事务。
在 140,000 条一一对应的源数据和投影记录上，比较六种范围与三种类型过滤的
完整响应及游标。要求使用明确归属本任务的固定本地容器和新的报告路径；
候选查询保留原有 8 秒预算。该结果仅证明本地读取规模，不代表生产 p95。
执行方式及上线验证边界见 `docs/agents/repo-validation.md` 的 Portal display
qualification 小节。

### Facets 与 Navigation 验证（Database #864）

这组 collector 只接受明确归属本任务的本地 `portal-facets-864`、PostgreSQL
17.11、指定 ownership receipt 和新的私有输出路径，不接受托管 DSN 或凭据。
`--smoke` 使用小型正确性 fixture；容量验证必须不带该参数。可重复传入 `--case`
选择查询形状。

```bash
python3 scripts/benchmark_portal_facets_navigation.py \
  --container supabase_db_portal-facets-864 --base-ref <exact-predecessor> \
  --candidate supabase/migrations/20261025052607_optimize_portal_facets_navigation.sql \
  --process-datasets 10000 --flow-datasets 69000 --card-padding 3072 \
  --samples 10 --report <new-private-serial-json>
python3 supabase/tests/upgrade/test_portal_facets_navigation_upgrade.py \
  --container supabase_db_portal-facets-864 --base-ref <exact-predecessor> \
  --report <new-private-upgrade-json>
python3 supabase/tests/upgrade/test_portal_facets_navigation_upgrade.py \
  --container supabase_db_portal-facets-864 --base-ref <exact-predecessor> \
  --committed-visibility --report <new-private-visibility-json>
```

committed-visibility 模式会保留真实 fixture，必须对本任务独占环境执行 reset。
随后并发 profile 使用准确且成功的串行报告与候选文件：

```bash
python3 scripts/benchmark_portal_facets_navigation_concurrent.py \
  --container supabase_db_portal-facets-864 --base-ref <exact-predecessor> \
  --reference-report <successful-serial-json> \
  --candidate supabase/migrations/20261025052607_optimize_portal_facets_navigation.sql \
  --rounds 3 --report <new-private-concurrent-json>
```

串行测试回滚；并发测试恢复候选 readers，但保留已提交的合成 fixture，由主代理
仅对本任务环境执行 reset。两者保留 4 MB session work_mem、既有函数覆盖值和
8 秒请求预算。完整正确性、性能与清理要求见 repo validation guide。

### 原生 Flow CAS 验证（Database #869）

同一个明确归属本任务的本地项目支持显式 CAS profile。升级验证及每种 cutover
模式都从准确 Main 前序、规范且空的独占环境开始，不接受托管目标。升级 profile
自行加载按序 prepare/activate 迁移，并分别记录原始 SQL 演练与 migration 历史。

```bash
python3 supabase/tests/upgrade/test_portal_facets_navigation_upgrade.py \
  --profile 869 --container supabase_db_portal-facets-864 \
  --base-ref 6a880838efbf4d453103a1141e9282db130171e8 \
  --report <new-private-upgrade-json>
python3 supabase/tests/upgrade/collect_portal_flow_cas_cutover.py \
  --mode reader-cutover --container supabase_db_portal-facets-864 \
  --base-ref 6a880838efbf4d453103a1141e9282db130171e8 \
  --report <new-private-cutover-json>
```

cutover collector 还支持 `--mode fence`，观察真实 writer 的锁顺序；以及
`--mode cost`，记录根语句 buffers/WAL 和包含 trigger 执行的时长。根 ModifyTable
WAL 不含 AFTER trigger 内的 navigation 写入，不能证明原生索引的写放大。
各模式之间仅重置本任务独占项目。
提交型模式保留 fixture，并验证 session/helper/lock 清理。完整要求及真实提交锁
时长与回滚演练的区别，见 validation guide。

独立 nested-WAL collector 从规范空前序环境开始，通过真实源 CAS 更新触发
navigation UPSERT。每个 variant 固定预热一次，再各测三次单行及三行批量更新；
每个准确根 WAL 事件只累计一次，相同 SQL 的不同调用分别保留。结果覆盖 navigation
heap 及全部索引维护，不是 CAS 索引独占字节、整个 trigger tree 或总体吞吐量。
嵌套 profiling 时长仅供诊断；独立 `cost` 模式的源语句执行时间包含 trigger 执行。
日志有大小上限，仅在实际源更新窗口启用。schema、metadata 与逻辑数据全部回滚；
物理页可能保留，其他验证前必须由 owner reset 独占环境。

```bash
python3 scripts/collect_portal_flow_cas_writer_wal.py \
  --container supabase_db_portal-facets-864 --report <new-private-writer-wal-json>
```

独立 DDL-fence collector 要求再次从规范空前序环境开始，观察普通及 concurrent
准确索引创建在 activation preflight 前被 navigation fence 阻塞，并确认普通
读取仍可执行；随后校验 B 创建的 witness 与完整响应。它保留已提交的 fixture
及原生 schema，供 owner reset，不改变 migration ledger。

```bash
python3 supabase/tests/upgrade/collect_portal_flow_cas_ddl_fence.py \
  --container supabase_db_portal-facets-864 \
  --base-ref 6a880838efbf4d453103a1141e9282db130171e8 \
  --report <new-private-ddl-fence-json>
```

独立的固定容量 collector 同样从准确、规范且空的前序环境开始，提交密集 CAS
合成 fixture 及两份真实迁移，记录阶段时钟、实际持锁模式、索引/表大小及完整
对照响应。报告时长包含观测开销；它不写 migration ledger，保留数据和原生
schema，供环境 owner 准确 reset，不证明并发负载或真实 writer 吞吐。

```bash
python3 scripts/collect_portal_flow_cas_volume_upgrade.py \
  --container supabase_db_portal-facets-864 --report <new-private-volume-json>
```

原生读取基准开始前，先通过本地 migration CLI 把两份真实迁移应用到独占空库。
collector 检查已安装的列、索引、既有 writer、强制 RLS 与 ACL，不创建产品 DDL；
它在同一最终物理 schema/writer 上比较前序与候选 reader。

```bash
python3 scripts/benchmark_portal_facets_navigation.py \
  --container supabase_db_portal-facets-864 \
  --base-ref 6a880838efbf4d453103a1141e9282db130171e8 \
  --candidate supabase/migrations/20261025103800_activate_portal_flow_cas_fact.sql \
  --fixture-profile cas-dense --native-cas-fact \
  --process-datasets 10000 --flow-datasets 69000 --card-padding 3072 \
  --samples 10 --plan-min-ms 1 --report <new-private-native-serial-json>
python3 scripts/benchmark_portal_facets_navigation_concurrent.py \
  --container supabase_db_portal-facets-864 \
  --base-ref 6a880838efbf4d453103a1141e9282db130171e8 \
  --reference-report <successful-native-serial-json> --native-cas-fact \
  --candidate supabase/migrations/20261025103800_activate_portal_flow_cas_fact.sql \
  --rounds 3 --report <new-private-native-concurrent-json>
```

并发测试前，把独占项目重建到相同原生 migration 状态；source/fixture/schema
准确 hash 必须与成功的串行 receipt 一致。不传 `--case` 会包含所需全部原生容量
形状和对照。原生并发的自定义选择必须保留全部十八个默认 CAS/对照场景；可以增加
场景，缺失时会在数据库准入前拒绝。`--smoke` 仅用于正确性诊断。collector 强制验证密集 fixture 分布、
稀有 CAS 的自然索引计划、相对性能和两秒本地目标。读取对比不测量迁移或 writer
成本，也不代表托管 p95。

### 计算导出升级验证

`render_calculation_export_upgrade.py <output.sql>` 只生成绑定准确基线和迁移文件的 populated fixture，不连接数据库。`test_calculation_export_upgrade.sh` 只在匹配的临时 GitHub-hosted workspace 中、显式允许隔离重置后执行，验证既有任务/结果/包/快照不变、导出租约和不可变输入绑定。基线与恢复顺序见 validation guide。

### Study 来源重试回归

在任务所有的 PG17 项目完成规范重建后运行：
```sh
python3 -B supabase/tests/regression/20261103_study_source_concurrency.py --report <new-source-concurrency-json>
```
测试观察两个真实会话的 Study/job 锁等待，要求同一租约返回相同不可变 packet，
恢复原 source-enabled 标记，并仅保留专用合成命名空间供明确的任务 reset。
input-parity SQL 套件另行覆盖非字符串来源 ID、规范化整数代际及普通任务类型归一化。
这些测试不授予 hosted 操作或业务数据权限。

## 审核元数据 Schema 检查

`python3 scripts/check_review_metadata_contract.py` 检查 Schema 引用是否完全本地化，
以及迁移内嵌内容是否与契约一致。可选参数 `--sdk-assets <directory>` 从已安装的
SDK 0.5.0 资源重新生成投影并核对来源哈希。此命令不访问网络、不操作数据库、
不安装依赖，也不修改文件。

### Study 方法评估与声明证据（Database #912）

使用独立 PG17 项目 `study912`（API56921/DB56922）和固定 CLI2.117.0。
`prepare_study_method_project.py --destination <新目录>/study912` 仅生成配置及
所有权清单；可用 `--through-version` 选择已存在的精确前置迁移。所有 CLI
操作必须显式指定该工作目录，不能操作保留的 study894/906/909 或共享项目。

按英文脚本说明依次执行 `test_study_method_upgrade.py`、
`20261104_study_method_concurrency.py`（输出实际服务 DTO）、
`test_study_method_serialization.py` 和 `20261104_study_method_transport.py`。
升级脚本在 `STUDY_METHOD_ALLOW_RESET=owned-study912` 下将已核实的项目重建到 Study 的精确迁移前缀。完整数据库契约任务校验当前 checkout 的最新迁移。竞争与 HTTP 脚本保留其合成命名空间并释放会话。

结构验证使用已安装的 pg_jsonschema0.3.3；固定 Worker 文件字节保持不变。
仅在所有引用均为本地片段后，在内存中提供绝对根 URI，解决验证器的解析
基地址要求，不改变约束或引入依赖。声明证据始终为 recorded_unverified。
SQL、本地签名 JWT 和模式验证不能替代真实 OAuth、原生计算、Storage 字节、
签名、科学方法或生产资格。

保留回执后，仅清理此任务明确拥有的命名空间，再空库重建并连续两次生成
五模式工作区与 public/api 类型。导出必须指定已核实的 study912 数据库 URL；
无参数 local 导出指向共享项目。结束时按精确项目标签执行受治理资源清理，
验证容器、卷及网络均为零，或记录明确的保留交接。

### `benchmark_portal_read_demand.py`

仅在明确归属 #925 的本地 PG17.11 栈中，回滚式比较完整导航与按需分支/总数读取。
不接受远程 DSN，拒绝非空数据及已有输出文件。`--report <新的JSON>` 保留
15.7 万版本下的完整计数对照、耗时和有界嵌套计划。规模测试前后均重建空库；
本地结果不能代替托管恢复证明，验收阈值见验证指南。


### `benchmark_portal_branch_visibility.py`

在明确归属 #925 的本地 PG17.11 栈中比较前后版本的完整分支响应。
传入精确的 `--base-ref`、新的 `--report` JSON 路径，以及可选的
`--samples`（2–5，默认 3）。在 15.7 万版本、300 种组合上交替运行，
保存源码哈希、完整响应对照、性能阈值及独立的自然执行计划，最后验证回滚清理。
不接受托管 DSN；与同一栈的其他测试串行运行。托管性能和流量来源仍需单独验证。

词法可见性优化还须运行 `benchmark_portal_lexical_keys.py`，加上
`--compare-scope-bridge`，将精确前驱中的作用域桥接函数一起纳入对照，并增加
只返回分支的 RPC 覆盖。前驱必须已包含该桥接函数；重载函数定义各自保留 SQL
终止符。
