# 003 · 接真 ASR：跟读录音 → 真转写

Triage: ready-for-agent
Type: AFK（真机麦验证为 HITL 尾）
Status: Ready

## What to build

把 `PracticeSpeechRecorder`（`StudioMac/Speech/`）的转写桩（现返回空串）换成真识别器。录音已是真的（`AVAudioRecorder`），补上端侧识别（iOS 26 / macOS 的 `SpeechAnalyzer`，回落 `SFSpeechRecognizer`），跟读完返回真文本。

保持现有 API 不变（`start` / `stopAndTranscribeKeepingAudio(language:)` / `cleanupAudio(at:)` / `cancel`），发音屏调用方无需改动。

## Acceptance criteria

- [ ] `PracticeSpeechRecorder` 接真识别（`SpeechAnalyzer` 起步，回落 `SFSpeechRecognizer`），返回非空转写
- [ ] 麦克风 + 语音识别权限到位（补 `NSSpeechRecognitionUsageDescription`；麦克风描述已有）
- [ ] 录音文件仍保留供音高分析（`audioFileURL` 有效，供 #004）
- [ ] 无语音 / 识别失败时优雅降级（不崩、给提示）
- [ ] 真机：mac 上说一句 → 看到转写文本（HITL）

## Blocked by

None - can start immediately
