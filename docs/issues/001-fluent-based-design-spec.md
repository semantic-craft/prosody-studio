# 001 · 基于 fluent 的产品/UX 设计 spec

Triage: ready-for-human
Type: HITL
Status: Ready

## What to build

探究 `reference/fluent`（Claude Code 的语言学习方法论套件：间隔重复 / 主动回忆 / 进度追踪，见其 `LEARNING_SYSTEM.md` / `PRACTICE.md`），据此确定 prosody-studio 作为独立 app 的产品形态与 macOS UX。

要回答：练习闭环（听原声 → 看韵律 → 跟读 → 反馈 → FSI 操练 → 间隔复习）怎么组织成屏幕与信息架构？现有从 responsay 迁移来的两屏（`PronunciationScreen` / `StudioScreen`）保留、改造，还是替换？mac 与 iOS 的体验差异？

产出一份 spec（`docs/spark/` 或 `docs/specs/`），作为后续 UI 实现 issue 的依据。建议用 `/spark`（探意图 → 写 spec → 停）。

## Acceptance criteria

- [ ] 读过 fluent 的 `LEARNING_SYSTEM.md` / `PRACTICE.md`，提炼出可落地的学习方法论要点
- [ ] 定义 prosody-studio 的练习闭环 + 屏幕信息架构（mac 优先，iOS 跟进）
- [ ] 对现有迁移屏给出明确取舍：保留 / 改造 / 替换
- [ ] spec 落盘并经用户评审通过
- [ ] 据 spec 再 `/to-issues` 拆 UI 实现 issue（本 issue 只产出 spec，不含实现）

## Blocked by

None - can start immediately
