# prosody-studio — 溯源与状态（Phase 1）

## 来源（2026-06-14 提取）

- **源仓**：`~/Projects/responsay`
- **源分支**：`reconcile/fireredasr2-into-main`
- **源 commit**：`9f5dc885` — *fix(capsule): show the latest dictated words in the live preview (truncate head)*（2026-06-13 23:00）
- 提取方式：**只读拷贝**（`cp`），responsay 未被修改。

### 平行 worktree（**未纳入**，仅记录）

用户另有 worktree `responsay-menubar-models` / 分支 `feat/menubar-model-switcher`：菜单栏 ASR+LLM 模型切换器 + **Qwen 端点修复**。这些是 ASR/LLM 路由，**不碰韵律域**，故本次提取的 5 个域模块与之无差异。

- ⏳ **TODO（Phase 3）**：把那条 Qwen 修复带进本仓 LLM 配置 —— Qwen LLM PayAsYouGo 端点 `/api/v1` → `/compatible-mode/v1`（源在 `ProviderCatalog+Presets.swift`）。

## 已拷入

| 区 | 内容 |
|---|---|
| 域模块（Core） | Prosody · FollowRead · Repeat · AdaptiveDrill · Learning |
| 地基（Core，先带全后剪） | Models · Audio · TTS · LLM · Persistence · Security · Services · StylePack · Brand · Translate |
| 语音地基 | ResponsaySpeech：AppleSpeechCaptureService · CloudTTS · RealtimeAudioSink · AudioInputDeviceSelector |
| 练习室 UI | StudioMac/MainWindow 7 文件 + Theme/SettingsTheme + DesignSystem/* |
| iOS 壳 | StudioiOS/（responsay `Responsay/` 整套：App/Features/Services/DesignSystem） |
| 设计参照 | reference/fluent（m98/fluent，浅克隆，已 gitignore） |

## 已剪（§2 边界：留在 responsay，不进本仓）

- Core：LegalBrain · OCR · Capture · Hotword · Dictionary · Selection · Streaming · Realtime · Output · Overview · Diagnostics
- ResponsaySpeech：Volcengine / FunASR / CloudQwen 云端听写 ASR
- Package.swift：移除 `LegalBrain/LegalSkills` 资源引用 + `ResponsayMaintenance` 维护 CLI

## 待办（Phase 3 — 让它真正跑起来）

- [ ] 重命名包/模块 `ResponsayCore`→`StudioCore`、`ResponsaySpeech`→`StudioSpeech`（现保留原名以使拷来的 `import` 不破）
- [ ] 修剪被删目录留下的悬挂引用，使 StudioCore 编译通过
- [ ] 剪 Tests/ 里属于已删模块的死测试
- [ ] 验证 `project.yml` 能 `xcodegen generate` 并 build mac/iOS target
- [ ] 折入 Qwen 端点修复（见上）
- [ ] 基于 reference/fluent 的 LEARNING_SYSTEM / PRACTICE 重做 macOS app 设计

> **状态**：Phase 1 = 拷核心 + 建骨架。**不保证编译**（设计如此）。Package.swift 的 manifest 已 `swift package dump-package` 校验合法。
