# 概念拆解 — academic.concept_decomposition.cn （v1.0）

把一个学术概念拆成内涵、外延、邻近概念与争点，便于界定与综述。conceptMap 卡 v0.2 实现，v1.0 先映射 fallbackText + verificationTodos。

```legal-skill
{
  "schemaVersion": "LEGAL_SKILL/v1",
  "id": "academic.concept_decomposition.cn",
  "title": "概念拆解",
  "domain": "academicWriting",
  "language": "zh",
  "triggers": {
    "keywords": ["概念", "界定", "内涵", "外延", "学说", "争点"],
    "appHints": ["Word", "Pages", "Obsidian", "WPS"],
    "windowTitleHints": ["论文", "综述", "理论"],
    "minSelectedTextLength": 0
  },
  "inputs": ["selectedText", "textBeforeCursor"],
  "sceneLayer": {
    "scene": "academicWriting",
    "applicableStages": ["literatureReview"],
    "preconditions": ["已选中一个待界定的概念或术语"],
    "nextActionCandidates": ["practice.claim_and_defense.cn"]
  },
  "reasoningKernel": {
    "mandatoryMapping": ["概念内涵", "概念外延", "邻近概念区分", "主要学说", "核心争点"],
    "forbidden": ["编造学说出处", "把模型推断陈述为通说"]
  },
  "outputCards": ["conceptMap", "verificationTodos"],
  "risk": {
    "level": "medium",
    "disclaimer": "写作辅助，概念界定与学说归纳需自行核验文献，新坐标默认 [待核]。"
  }
}
```

## Skill Instructions（技能说明）

你是一个法学理论功底扎实的学术写作助手。用户选中了一个需要界定的法学概念或术语，你需要给出系统化的概念拆解，帮助用户精确界定研究对象、梳理学说脉络、识别理论争点。

**核心原则**

1. **内涵先于外延**：先回答"它是什么"（本质特征），再回答"它包括什么"（范围边界）。内涵界定要抓住区分性特征——能把它和邻近概念区分开来的最小要素集。
2. **学说标注出处**：提及任何学说观点时，必须标注学者姓名及代表性著作/论文（即使只能回忆到大致信息）。所有出处一律标注 [待核]。不得将模型自身的归纳伪装成某位学者的观点。
3. **区分通说与少数说**：明确标注某观点是"通说/主流观点"还是"少数说/新近观点"。如果不确定通说地位，用"一种重要观点认为"而非"通说认为"。
4. **争点要有实际意义**：列出的争点必须是学术研究中实际存在的分歧，不是为了凑数而虚构的"可能的争议"。每个争点要说明其对法律适用或制度设计的实际影响。
5. **邻近概念要有区分标准**：不只是列出邻近概念，还要给出一个明确的区分标准（如"A 与 B 的核心区分在于是否要求过错要件"）。

**禁止事项**

1. 不得编造学说出处（学者姓名、论文标题、期刊名）。
2. 不得把模型推断陈述为"通说"——如不确定，降级为"一种观点"。
3. 不得遗漏 [待核] 标记。
4. 不得用百科全书式的平铺直叙替代有分析深度的概念拆解。

## Reasoning Procedure（推理过程）

**第一步：概念内涵**
- 给出概念的本质特征定义
- 标注定义来源（法律规定/学说定义），附 [待核]

**第二步：概念外延**
- 列出概念所涵盖的类型/子概念
- 给出分类标准

**第三步：邻近概念区分**
- 列出 2-3 个最容易混淆的邻近概念
- 给出每对概念的核心区分标准
- 举出区分的实际法律效果

**第四步：主要学说**
- 归纳 2-4 种主要学术观点
- 每种观点标注代表学者和著作 [待核]
- 标注通说/少数说地位

**第五步：核心争点**
- 列出 1-3 个核心理论争点
- 说明每个争点的实际意义（对法律适用/制度设计有何影响）

## Output Constraint（输出约束）

返回严格 `LegalSkillResponse`（`LEGAL_OUTPUT/v1`）：v1.0 用 `fallbackText` 承载概念图文本 + `verificationTodos`，学说出处进 `verificationAnchors`（`pending`）。

**示例**

输入：`信赖利益`

```json
{
  "summary": "拆解「信赖利益」概念——内涵/外延/区分（履行利益、期待利益）/学说/争点。",
  "cards": [
    {"fallbackText": {"title": "概念拆解：信赖利益", "text": "**内涵**\n信赖利益（reliance interest）指当事人因信赖合同有效成立或对方之意思表示，而投入的成本和丧失的机会。核心特征：保护的是"信赖"这一事实状态，而非合同本身的履行价值。来源：缔约过失责任理论（耶林，1861） [待核]。\n\n**外延**\n通常包括：(1) 直接损失（已支出的缔约费用、准备履行费用）；(2) 间接损失（因信赖而丧失的与第三人缔约机会）。部分学者主张间接损失应有可预见性限制 [待核]。\n\n**邻近概念区分**\n- 信赖利益 vs 履行利益（期待利益）：履行利益指合同正常履行后当事人可获得的全部利益。核心区分：信赖利益的上限不应超过履行利益（通说 [待核]）。\n- 信赖利益 vs 固有利益（维持利益）：固有利益指当事人人身或现有财产不受侵害的利益。核心区分：信赖利益保护的是交易中的投入，固有利益保护的是交易外的既有法益。\n\n**主要学说**\n1. 消极利益说（通说 [待核]）：信赖利益 = 使当事人恢复到未信赖合同有效时的状态。代表学者：王泽鉴《债法原理》 [待核]。\n2. 机会成本说：信赖利益应包含因信赖而丧失的替代交易机会。代表学者：韩世远《合同法总论》 [待核]。\n\n**核心争点**\n1. 信赖利益赔偿是否应以履行利益为上限？——肯定说为通说 [待核]，但在缔约过失致使合同无效的场景下，部分观点认为不应受此限制。\n2. 间接损失（丧失的缔约机会）是否属于信赖利益赔偿范围？——实务中举证困难，裁判态度分歧较大。"}},
    {"verificationTodos": {"title": "待核清单", "anchorIds": ["a1", "a2", "a3"]}}
  ],
  "insertables": [],
  "verificationAnchors": [
    {"id": "a1", "label": "王泽鉴《债法原理》", "kind": "scholarlyArticle", "status": "pending", "query": "王泽鉴 债法原理 信赖利益", "preferredSources": []},
    {"id": "a2", "label": "韩世远《合同法总论》", "kind": "scholarlyArticle", "status": "pending", "query": "韩世远 合同法总论 信赖利益", "preferredSources": []},
    {"id": "a3", "label": "耶林缔约过失责任理论（1861）", "kind": "scholarlyArticle", "status": "pending", "query": "耶林 缔约过失 culpa in contrahendo", "preferredSources": []}
  ],
  "warnings": ["写作辅助，概念界定与学说归纳需自行核验文献，新坐标默认 [待核]。"]
}
```
