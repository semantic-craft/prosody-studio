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

## Phase 3 — 让它编过跑起来（已完成 2026-06-14）

**关键发现**：responsay 的 `ResponsayCore` 是个**单体包**——韵律域、地基、法律、OCR、输入法全在一个 SPM target 里互相依赖。Phase 1 的「curated 子集」（删了 legal/OCR/输入法目录）导致 **5481 个悬挂引用**（StylePack/Persistence/Services/LLM/TTS 都引用被删类型）。干净抽出韵律域 = 要把单体拆成子包 = 大重构，非机械。

**采用的解法（先带全后剪）**：用最后绿的 `c42bbce7`（含韵律域 + Qwen 端点修复）的**完整 Core** 替换 curated 版 → 包立即编过。法律/OCR/输入法作为暂时负重，留待 fluent 重设计时剪。

- ✅ **StudioCore 包**：`swift build` 通过（26 模块，含韵律域）。
- ✅ **StudioiOS**：`** BUILD SUCCEEDED **`（用拷来的 iOS 壳 + 完整 Core）。
- ✅ **StudioMac**：`** BUILD SUCCEEDED **`。补了 `@main` 壳 `StudioMac/App/ProsodyStudioApp.swift`（TabView 托两个屏）+ app-glue 垫片 `StudioAppGlue.swift`（`Diag`→OSLog、`TTSEngine`→stub）+ `PracticeSpeechRecorder` 改 stub（录音真、转写桩）——避开 sherpa-onnx 原生链 + BYOK 凭据链。
- Qwen 端点修复随 `c42bbce7` 一并带入（无需单独折入）。

## 待办（Phase 4 — 收拾负重 + 真正成形）

- [ ] **剪单体负重**：把 Core 拆成子包 / 删韵律 app 用不到的 legal/OCR/输入法/云听写模块（需依赖闭包分析）。
- [ ] **接真引擎**：把 `TTSEngine`/`PracticeSpeechRecorder` 垫片换成真 TTS（朗读）+ 真 ASR（跟读转写），跑通音高/升降调对比反馈。
- [ ] 重命名包 `ResponsayCore`→`StudioCore`（现保留原名使 `import` 不破）。
- [ ] 基于 `reference/fluent`（LEARNING_SYSTEM / PRACTICE 方法论）重做 macOS app 设计。
- [ ] HITL：真机麦克风跑一遍跟读/朗读（headless 测不了音频）。

> **状态**：Phase 1（拷核心）→ Phase 2（瘦身 responsay，已合 main）→ **Phase 3（两 target 编过，本仓）已完成**。负重未剪、引擎为桩——设计上先跑起来，成形是 Phase 4。
