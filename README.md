# prosody-studio（暂名）

英语**韵律练习室** —— 从 [responsay](../responsay) 拆出的独立 app：

- 🎵 **韵律可视化**：升降调（rise/fall）· 重读/弱读 · 音节连读，五线谱式呈现
- 🗣️ **发音练习**：听原声 → 跟读 shadowing → 复读，标升降调/重音偏差
- 🧠 **FSI 自适应操练**：用真实错误出题 · 间隔复习（SM-2）· 难度自适应

目标平台：**macOS + iOS**。学习闭环受
[`m98/fluent`](https://github.com/m98/fluent) 启发，但已按英语口语练习场景独立改写；
产品取舍、代码映射与许可边界见 [`docs/specs/learning-loop.md`](docs/specs/learning-loop.md)
和 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)。本仓不依赖或保存 Fluent 的本地克隆。

## 与 responsay 的关系：零交集

本仓与 responsay **不共享任何代码/包/依赖**。地基（LLM/TTS/Audio/Models/Persistence/BYOK）是一次性**拷贝**，各自独立演进。responsay 自此专注 **macOS 输入法**（ASR/LLM/TTS + 法律/英文/Coach 技能）。

拆分设计与计划见 responsay 仓的 `docs/spark/2026-06-14-prosody-studio-split-design.md`。

## 结构

```
Packages/ResponsayCore/   # 共享地基 + 韵律域（待 Phase 3 改名 StudioCore）
StudioMac/                # macOS 练习室 UI（韵律/发音/操练 7 屏 + 主题）
StudioiOS/                # iOS 壳（从 responsay Responsay/ 搬来的种子）
docs/specs/               # 产品规格（含学习闭环与来源边界）
project.yml               # XcodeGen（mac + iOS 双 target，待验证）
NOTES.md                  # 溯源 + 待办
```

## 状态

**Phase 3 已完成（2026-06-14）：mac + iOS 两个 target 都 `BUILD SUCCEEDED`。** Core 用 responsay 最后绿提交的完整版（先带全后剪）；TTS/ASR 暂为桩，法律/OCR/输入法为暂时负重。收拾负重 + 接真引擎 + 按学习闭环规格重设计 = Phase 4。详见 `NOTES.md`。
