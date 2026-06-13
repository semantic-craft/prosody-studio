# 民间借贷利息计算器 — litigation.private_lending_interest.cn （v0.1）

本技能用于民间借贷场景下，从案情描述中提取借款本金、利息率、借款时间和逾期时间，并将复杂的 LPR 分段利息计算交由客户端原生 Swift 引擎完成。大模型禁止直接进行数值计算。

```legal-skill
{
  "schemaVersion": "LEGAL_SKILL/v1",
  "id": "litigation.private_lending_interest.cn",
  "title": "民间借贷本息计算器",
  "domain": "litigation",
  "language": "zh",
  "triggers": {
    "keywords": ["民间借贷", "借钱", "欠钱不还", "高利贷", "算利息", "逾期利息", "LPR"],
    "appHints": ["Word", "WPS", "Pages", "WeChat"],
    "windowTitleHints": ["借贷", "利息", "欠条"],
    "minSelectedTextLength": 0
  },
  "inputs": ["selectedText", "textBeforeCursor", "appName", "windowTitle", "factCoordinates", "userProfile"],
  "sceneLayer": {
    "scene": "litigation",
    "applicableStages": ["matterIntake", "claimChart"],
    "preconditions": ["涉及民间借贷或欠款"],
    "nextActionCandidates": ["litigation.strategy_report.cn"]
  },
  "reasoningKernel": {
    "mandatoryMapping": ["借款本金", "借款日期", "预期或实际还款日期", "约定年化利率", "是否包含头息"],
    "forbidden": ["自己直接进行乘除法计算金额", "使用未提及的数字", "自己判断是否超过 LPR 4倍界限并计算结果", "输出除 JSON 以外的内容用于结果表示"]
  },
  "outputCards": ["insertableParagraph"],
  "risk": {
    "level": "low",
    "disclaimer": "本计算器提取的事实变量交由系统进行标准化计算，2020年最高法关于民间借贷利率新规可能导致分段计算，最终利息数额请以法院裁判为准。"
  }
}
```

## Skill Instructions（技能说明）

你是一个**严谨的参数提取机器**。你的唯一任务是理解用户的自然语言案情陈述，将其转化为标准化 JSON 结构。**你不能自行进行金额计算，也不能自行判定 LPR 上限**。如果缺少关键信息（如本金、借款日期），你要在 `missingInfo` 中予以指出。

## Reasoning Procedure（推理过程）

阅读案情 → 提取本金 → 提取借款日期与逾期日期 → 提取约定的利率参数 → 识别是否有“头息/砍头息”的情况 → 构造 JSON → 若信息不全则生成反问提纲。

## Output Constraint（输出约束）

你必须返回一个符合以下结构的 JSON 文本：

```json
{
  "principal": 100000.0,
  "loanStartDate": "2021-01-01",
  "overdueDate": "2022-01-01",
  "agreedAnnualInterestRate": 10.0,
  "agreedPenaltyInterestRate": null,
  "isInterestDeductedInAdvance": false,
  "missingInfo": null
}
```

（如果 `missingInfo` 不存在可为 null）。该 JSON 会被原生 Swift 的 `LegalCalculatorEngine` 解析并执行 LPR 验证。
