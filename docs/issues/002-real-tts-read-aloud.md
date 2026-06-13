# 002 · 接真 TTS：朗读出声 + 词高亮

Triage: ready-for-agent
Type: AFK（真机音频验证为 HITL 尾）
Status: Ready

## What to build

把当前 `TTSEngine` 桩（`StudioAppGlue.swift` 里 throw）换成真合成器，让发音屏的「听原声」真出声，并按朗读时间轴驱动逐词高亮（`ReadAloudTimeline` → `ProsodyStaveView(activeWordIndex:)` 链路已随域模块迁移）。

端到端：句子 → 合成 → 播放 → 词高亮。起步用端侧零配置引擎（`AVSpeechSynthesizer`），不强求 BYOK 云端，开箱即用。保留 `ReadAloudController` 在合成失败时降级到 estimated timeline 的现有行为（UI 不破）。

## Acceptance criteria

- [ ] 接入一个真 TTS（端侧 `AVSpeechSynthesizer` 起步），替换 `TTSEngine`/`StudioTTSStub` 桩
- [ ] 发音屏「听原声」真出声
- [ ] 播放时按词高亮，与音频时间轴对齐；缺逐词时间戳时用估算时间轴
- [ ] 单元测试覆盖时间轴 / 高亮 index 逻辑（音频本身不在模拟器测）
- [ ] 真机：mac 上听到朗读 + 看到逐词高亮（HITL）

## Blocked by

None - can start immediately
