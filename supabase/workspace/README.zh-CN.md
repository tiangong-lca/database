---
title: 远程 Schema 工作区
docType: guide
scope: repo
status: active
authoritative: false
owner: database-engine
language: zh-CN
whenToUse:
  - 当任务涉及生成的 schema workspace 文件或刷新流程时
  - 当你需要判断 workspace 路径是生成视图还是稳定人工维护区时
whenToUpdate:
  - 当 workspace 刷新行为或稳定 overlay 规则变化时
  - 当支持的 migration 生成来源变化时
checkPaths:
  - supabase/workspace/README.zh-CN.md
  - supabase/workspace/**
  - scripts/**
  - docs/agents/repo-architecture.md
  - .githooks/pre-push
  - scripts/docpact-gate.sh
  - scripts/install-git-hooks.sh
lastReviewedAt: 2026-09-26
lastReviewedCommit: 5b6a2508dcfbe7c602f8cce848d1430a9796ddfa
lastReviewedNote: "Reviewed Database #723 main-hotfix narrow Portal readers, coverage cutover, real-writer/equivalence/concurrency proof and isolated fixture disposition. Public DTOs, writer/ACL contracts, 8-second budgets and main-to-dev/root delivery boundaries remain; local schema snapshots require exact reconstruction and deterministic regeneration."
related:
  - ../../AGENTS.md
  - ../../.docpact/config.yaml
  - ../../docs/agents/repo-architecture.md
  - ../../docs/agents/repo-validation.md
  - README.md
---

# 远程 Schema 工作区

这个目录用于保存 `dev` 数据库的最新远程 schema 导出，以及基于该导出拆分出来的可读工作区。

## 生成内容

执行 `python scripts/build_schema_workspace.py --environment dev` 时，会生成或刷新以下路径：

- `remote_schema.sql`
- `global/`
- `schemas/`

`database.types.ts` 由 `python scripts/build_database_types.py` 单独生成，只覆盖实际暴露的 `public` 与 `api` schema，并包含 Edge 使用的 service/authenticated 消费者 façade。

## 刷新行为

每次刷新 `supabase/workspace` 时，会执行以下操作：

- `remote_schema.sql` 会被最新导出的 dump 覆盖。
- 生成 SQL 的行尾空白会被规范化，使重复刷新产生稳定的审查 diff。
- `global/` 会被删除并按最新 dump 重新生成。
- `schemas/` 会被删除并按最新 dump 重新生成。
- `README.md` 会被保留。
- `changes/` 会被保留，适合作为手工修改且需要跨刷新保留的目录。
- 其他根目录文件当前也会保留，但建议只把 `README.md`、文档类文件和 `changes/` 当作稳定的人工维护位置。

## 重要注意事项

- 任何写在 `remote_schema.sql`、`global/` 或 `schemas/` 里的手工修改，下一次刷新时都会丢失。
- 这些路径下如果存在尚未提交到 Git 的改动，在刷新时也可能被覆盖或删除。
- 执行刷新命令前，先检查 `git status`，把需要保留的内容提交或暂存。
- 这个工作区应该被视为远程数据库的生成视图，而不是手工维护 schema 变更的真相源。

## 建议用法

- `remote_schema.sql` 适合查看完整原始导出。
- `global/` 和 `schemas/` 适合按对象结构浏览和审查。
- 如果你准备依赖 `python scripts/copy_workspace_file_to_changes.py --git-changes` 自动识别后续手工改动，应该先同步远程数据库并刷新 workspace，然后把新的 `supabase/workspace/schemas` 提交到 Git，再开始编辑。
- 需要修改的对象应先复制到 `changes/`，并尽量保持与 `schemas/` 相同的相对目录结构。
- 只有当源文件路径属于当前脚本支持的对象类型时，才应从 `changes/` 或 `supabase/model/schemas/` 生成 migration：
  - `functions/<name>/definition.sql`
  - `views/<name>/definition.sql`
  - `materialized_views/<name>/definition.sql`
  - `tables/<table>/policies/<name>.sql`
  - `tables/<table>/triggers/<name>.sql`
- `table.sql`、索引、sequence、schema 文件以及其他 workspace 文件，目前都不能直接作为 `new_migration.py` 的输入。
- 需要长期保留的说明、备注或操作约定，应写在 `README.md` 或其他根目录文档文件中，不要写进生成目录。

## 刷新命令

schema 边界迁移部署到 `dev` 后，应显式刷新仓库拥有的全部应用 schema：

```bash
python scripts/build_schema_workspace.py --environment dev \
  --schemas public api private util archive
```

远程 `dev` 仍是权威目标。无法直接导出远程 schema 时，可通过 CLI 原生 local 连接按本地已应用 migration 精确重建：

```bash
python scripts/build_schema_workspace.py --environment local \
  --schemas public api private util archive
```

Schema 变更 PR 可以把该 exact-local 结果作为审查快照提交，但必须先通过空库 migration 重建、定向合同测试，并再次生成证明无漂移；此时它还不代表托管来源。合并后必须确认数据库专用 Dev 部署到达准确 migration head、托管 catalog 检查通过，并把 remote-Dev 刷新结果与本快照比较；若有漂移，以后续提交收口。

随后应从同一个本地完整 migration 状态生成纳入版本控制的 Data API 类型合同：

```bash
python scripts/build_database_types.py --environment local
```

如果目标分支已经应用 `worker_jobs` cutover 和旧 job 表退休 migration，刷新后应确认生成内容不再展示已退休的 legacy job 表：

```bash
python scripts/check_generated_workspace_legacy_tables.py
```

## Local Docpact Push Gate

The repository now includes a local pre-push docpact gate in `scripts/docpact-gate.sh`. It is documentation-governance tooling and does not change database schema workspace behavior.
