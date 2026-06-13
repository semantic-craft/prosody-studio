# 004 · 音高/升降调对比反馈活化

Triage: ready-for-agent
Type: AFK（真机验证为 HITL 尾）
Status: Blocked

## What to build

把跟读录到的真音频接进已迁移的音高链，让升降调/重音偏差反馈从占位变真实：

录音 → `PitchContourExtractor`（Core，已有）抽 F0 → `PitchContourComparator`（Core，已有）对比目标轮廓 → 渲染 `FollowReadFeedbackView` 的偏差图（`PitchOverlayGeometry`，已有）。

这条逻辑链随域模块整体迁移、已有单测覆盖，缺的只是把 #003 的真录音喂进去并对齐词边界。端到端：跟读 → 音高曲线对比 → 看到真实偏差反馈。

## Acceptance criteria

- [ ] 跟读录音喂入 `PitchContourExtractor` 得到真 F0 轮廓
- [ ] 与目标句的目标轮廓对比，`FollowReadFeedbackView` 显示真实偏差（非占位数据）
- [ ] 边界：静音 / 过短 / 无基频段不崩
- [ ] 既有 `PitchContourComparatorTests` / `PitchOverlayGeometryTests` 保持绿
- [ ] 真机：跟读一句 → 看到升降调偏差图（HITL）

## Blocked by

- #003 接真 ASR：跟读录音 → 真转写（需真录音 + 词边界对齐）
