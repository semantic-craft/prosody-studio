# Issues · prosody-studio（英语韵律练习室）

> Phase 4 backlog. Phase 1–3 已完成（从 responsay 抽出独立仓；mac+iOS 两 target `BUILD SUCCEEDED`；引擎为桩）。背景见 `../../NOTES.md`。
> 约定沿用 responsay：编号 `NNN-slug.md`；`Triage:` 行 = AFK 就绪轴（`ready-for-agent` / `ready-for-human` / `needs-info` / `wontfix`），与下面 Status 的成熟度轴分开。

## Board

| ID | Status | Type | Issue | Blocked by |
|---|---|---|---|---|
| 001 | Review | HITL | [基于 Fluent 启发的产品/UX 设计 spec](001-fluent-based-design-spec.md) | — |
| 002 | Ready | AFK | [接真 TTS：朗读出声 + 词高亮](002-real-tts-read-aloud.md) | — |
| 003 | Ready | AFK | [接真 ASR：跟读录音 → 真转写](003-real-asr-shadow-transcription.md) | — |
| 004 | Blocked | AFK | [音高/升降调对比反馈活化](004-pitch-intonation-feedback.md) | 003 |
| 005 | Blocked | AFK | [剪单体负重：删 app 用不到的 Core 模块](005-trim-monolith-baggage.md) | 002, 003, 004 |
| 006 | Blocked | AFK | [改名 ResponsayCore→StudioCore](006-rename-studiocore.md) | 005 |

> 后续 UI issue 待 #001 草案经用户评审后再校准，避免把未冻结的信息架构提前固化。
