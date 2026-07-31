# 001 · 基于 Fluent 启发的产品/UX 设计 spec

Triage: ready-for-human
Type: HITL
Status: Draft ready for human review

## What to build

研究 [`m98/fluent`](https://github.com/m98/fluent)（Claude Code 的语言学习方法论套件：间隔重复 / 主动回忆 / 进度追踪），据此确定 prosody-studio 作为独立 app 的产品形态与 macOS UX。产品不依赖本地 Fluent 克隆；来源、许可与独立改写边界记录在 [`THIRD_PARTY_NOTICES.md`](../../THIRD_PARTY_NOTICES.md)。

要回答：练习闭环（听原声 → 看韵律 → 跟读 → 反馈 → FSI 操练 → 间隔复习）怎么组织成屏幕与信息架构？现有从 responsay 迁移来的两屏（`PronunciationScreen` / `StudioScreen`）保留、改造，还是替换？mac 与 iOS 的体验差异？

当前草案：[`docs/specs/learning-loop.md`](../specs/learning-loop.md)。它是后续 UI 实现 issue 的依据，须经用户评审后才冻结。

## Acceptance criteria

- [x] 读过 Fluent 的 `LEARNING_SYSTEM.md` / `PRACTICE.md`，提炼出可落地的学习方法论要点
- [x] 定义 prosody-studio 的练习闭环 + 屏幕信息架构（mac 优先，iOS 跟进）
- [x] 对现有迁移屏给出明确取舍：保留 / 改造 / 替换
- [x] spec 草案落盘
- [ ] 用户评审并冻结 spec
- [ ] 评审后校准后续 UI issue；本 issue 不直接实现 UI

## Blocked by

None - can start immediately
