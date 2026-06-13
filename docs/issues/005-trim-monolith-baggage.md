# 005 · 剪单体负重：删 app 用不到的 Core 模块

Triage: ready-for-agent
Type: AFK
Status: Blocked

## What to build

prosody-studio 现整份带了 responsay 的单体 `ResponsayCore`（含 `LegalBrain` / `OCR` / 输入法 / 云听写 等韵律 app 用不到的模块）——这是 Phase 3「先带全后剪」为了编过的临时负重。

引擎接真（#002 / #003 / #004）后，韵律 app 的真实依赖闭包就清楚了，据此剪负重：要么整批删用不到的模块，要么把 Core 拆成「prosody 域 + 它需要的地基」子包。目标是更小、更聚焦、更像独立韵律 app 的包，且构建与现有功能保持绿。

> 注意 `Learning` 的共享 SRS（`SM2Scheduler` / `ReviewGrade` / `MasteryStars`）等地基仍要保留。

## Acceptance criteria

- [ ] 算出 prosody 域 + 三个 app target 的真实依赖闭包
- [ ] 删除 / 隔离用不到的模块（legal / OCR / 输入法 / 云听写 等），无悬挂引用
- [ ] StudioCore 包 + StudioMac + StudioiOS 仍 `BUILD SUCCEEDED`
- [ ] 保留功能（朗读 / 跟读 / 音高 / 操练 / 复习）无回归
- [ ] `NOTES.md` 记录删了什么、为什么

## Blocked by

- #002 接真 TTS
- #003 接真 ASR
- #004 音高反馈活化

（接真后才知道真用到啥，避免删了引擎需要的地基）
