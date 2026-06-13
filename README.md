# prosody-studio（暂名）

英语**韵律练习室** —— 从 [responsay](../responsay) 拆出的独立 app：

- 🎵 **韵律可视化**：升降调（rise/fall）· 重读/弱读 · 音节连读，五线谱式呈现
- 🗣️ **发音练习**：听原声 → 跟读 shadowing → 复读，标升降调/重音偏差
- 🧠 **FSI 自适应操练**：用真实错误出题 · 间隔复习（SM-2）· 难度自适应

目标平台：**macOS + iOS**。设计基底参照 [`m98/fluent`](https://github.com/m98/fluent)（`reference/fluent/`）。

## 与 responsay 的关系：零交集

本仓与 responsay **不共享任何代码/包/依赖**。地基（LLM/TTS/Audio/Models/Persistence/BYOK）是一次性**拷贝**，各自独立演进。responsay 自此专注 **macOS 输入法**（ASR/LLM/TTS + 法律/英文/Coach 技能）。

拆分设计与计划见 responsay 仓的 `docs/spark/2026-06-14-prosody-studio-split-design.md`。

## 结构

```
Packages/ResponsayCore/   # 共享地基 + 韵律域（待 Phase 3 改名 StudioCore）
StudioMac/                # macOS 练习室 UI（韵律/发音/操练 7 屏 + 主题）
StudioiOS/                # iOS 壳（从 responsay Responsay/ 搬来的种子）
reference/fluent/         # 设计参照（gitignored，本地克隆）
project.yml               # XcodeGen（mac + iOS 双 target，待验证）
NOTES.md                  # 溯源 + 待办
```

## 状态

**Phase 1（拷核心 + 建骨架）已完成；尚不保证编译** —— 见 `NOTES.md`。让它真正构建/跑起来 = Phase 3。
