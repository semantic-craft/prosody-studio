# 006 · 改名 ResponsayCore→StudioCore

Triage: ready-for-agent
Type: AFK
Status: Blocked

## What to build

把包 / 模块名 `ResponsayCore`→`StudioCore`、`ResponsaySpeech`→`StudioSpeech`。Phase 1 为免拷来的 `import` 失效暂留了原名；瘦身（#005）后再改，避免对将删模块做无谓改名。

纯重构：更新 `Package.swift` 的 product / target 名 + 全部 `import` 语句 + `project.yml` 的依赖引用。

## Acceptance criteria

- [ ] `Package.swift` 的 product / target 改名 `StudioCore` / `StudioSpeech`
- [ ] 全部 `import ResponsayCore` / `import ResponsaySpeech` → `Studio*`
- [ ] `project.yml` 依赖引用更新（含 StudioMac / StudioiOS target）
- [ ] 三个 target 仍 `BUILD SUCCEEDED`
- [ ] 无残留 "Responsay" 命名（溯源注释除外）

## Blocked by

- #005 剪单体负重（瘦身后再改名，免无谓 churn）
