---
title: database-engine
docType: overview
scope: repo
status: active
authoritative: false
owner: database-engine
language: zh-CN
whenToUse:
  - 当你只需要这个仓库的高层作用说明，而不需要完整 AI 契约面时
  - 当你从中文入口快速确认 repo 负责范围时
whenToUpdate:
  - 当 repo 目的、分支模型或负责边界发生变化时
  - 当这里列出的 AI 入口文档变化时
checkPaths:
  - README.zh-CN.md
  - AGENTS.md
  - .docpact/config.yaml
  - docs/agents/**
lastReviewedAt: 2026-11-06
lastReviewedCommit: 753e8c6a5ef1535bd751d5878b93ce458f0f573c
lastReviewedNote: "Database #926: reviewed generated schema/type export procedures for exact 7z descriptors; authorization and rollback unchanged."
related:
  - AGENTS.md
  - .docpact/config.yaml
  - docs/agents/repo-validation.md
  - docs/agents/repo-architecture.md
---

# database-engine

`database-engine` 是 TianGong LCA workspace 中用于管理 Supabase 数据库治理的仓库。

它负责维护已经提交到仓库中的数据库真相源：

- `supabase/config.toml`
- `supabase/migrations/*.sql`
- `supabase/seed.sql`
- `supabase/seeds/*`
- `supabase/tests/*.sql`
- `.env.supabase.dev.local.example`
- `.env.supabase.main.local.example`
- Supabase 分支与运维文档
- 不部署 schema 地修复并验证准确 PR Preview 的 PostgREST/匿名 Portal Hybrid 边界，并在合并后另行把已提交 migration 推送到持久化 Supabase `dev` 分支的 GitHub Actions 流程
- 自动应用 Git `main` migrations 的生产 Supabase GitHub integration 契约

它**不**负责以下内容：

- 前端运行时环境文件，例如 `.env` 或 `.env.development`
- 应用侧 Supabase client
- Edge Function 运行时代码
- 把在 Dashboard 上临时手工修改作为长期工作流

这些内容应保留在消费方仓库中，例如：

- `tiangong-lca-next`：前端环境文件与应用集成
- `tiangong-lca-edge-functions`：Edge Function 运行时代码

## 分支模型

- GitHub 默认分支：`main`
- 日常主干分支：`dev`
- 常规 PR 目标分支：`dev`
- 提升路径：`dev -> main`

## 快速开始

1. 从最新的 `dev` 开始。
2. 基于 `dev` 创建功能分支。
3. 使用本地 Supabase 进行 schema 编写和验证。
4. 将 migrations、seeds、tests 和 config 变更一起提交。
5. 向 `dev` 发起 PR。
6. 验证 PR 对应创建的 Supabase 预览分支；同仓且具备仓库配置授权的 PR 会等待准确的 Supabase integration check，只修复该 Preview 的 PostgREST 运行态字段，并验证匿名显式 `api` Portal Hybrid 合同。
7. 合并后，验证持久化 `dev` 数据库，再通过 `tiangong-lca-edge-functions` 部署并验证目标 Dev Functions。
8. 准备发布时，将 `dev` 提升到 `main`，随后验证生产 Supabase 自动迁移。

## 运维环境文件

本仓库维护运维侧 Supabase 分支绑定模板：

- `.env.supabase.dev.local.example`
- `.env.supabase.main.local.example`

可将它们复制为 `.env.supabase.dev.local` 或 `.env.supabase.main.local`，用于本地私有凭据配置。
这些真实的 `.local` 文件会被 Git 忽略，因为其中可能包含远程数据库密码。
前端运行时环境文件应保留在 `tiangong-lca-next` 中。

仓库自动化使用 `SUPABASE_MAIN_PROJECT_ID` 准确解析 PR Preview 分支，并使用
`SUPABASE_DEV_PROJECT_ID` 完成隔离的持久化 Dev 部署与排除保护。同仓 Preview 门还
要求仓库管理的 `SUPABASE_ACCESS_TOKEN`；三项任一缺失都会 fail closed。secret 不进入
运维模板或 checked-in workflow payload。

## 文档

- AI 入口：`AGENTS.md`
- 机器可读治理：`.docpact/config.yaml`
- 验证指南：`docs/agents/repo-validation.md`
- 架构说明：`docs/agents/repo-architecture.md`
- 英文分支文档：`docs/agents/supabase-branching.md`
- 中文分支文档：`docs/agents/supabase-branching_CN.md`
