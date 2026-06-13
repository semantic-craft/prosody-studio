import Foundation

/// Swift port of backend `buildExpressPrompt` + `coachRegisterDirective` + `contextLines`
/// (地道英文 + 诊断). App-direct path (242, epic 238). Faithful to `backend/prompts.mjs`;
/// `ExpressionContext` already applies the per-field limits/dedup that backend
/// `normalizeExpressionContext` did, so we only reproduce the budget-priority assembly here.
enum ExpressPromptBuilder {
    /// Total character budget for the assembled context block (backend `CONTEXT_TOTAL_BUDGET`).
    static let contextTotalBudget = 1800

    static func build(
        intent: String,
        context: ExpressionContext?,
        register: CoachRegister
    ) -> (system: String, user: String) {
        let system = [
            "Role:\nYou are a bilingual English-speaking coach for a Chinese native speaker who wants to sound like a natural AMERICAN English speaker. The user gives an utterance they actually said (usually their own non-idiomatic English; sometimes Chinese intent).",
            "Target:\nidiomatic AMERICAN SPOKEN English (General American) — the everyday spoken register a real person uses out loud, tuned to the chosen 教练语域 (Register) below. Prefer phrasal verbs (find out, put off, figure out, come up with, reach out) plus natural collocations over Latinate/textbook words (discover, postpone, determine, devise, contact). Keep it the way someone would actually say it out loud.",
            coachRegisterDirective(register),
            [
                "Never a translation (hard rule — holds in EVERY register):",
                "- This is intent re-expression, not translation: guess what the speaker is trying to do, then say what a native would ACTUALLY say to do that here.",
                "- Do not transliterate or mirror the source wording word-for-word. The register only shifts the social formality of the native phrasing; it never licenses a literal translation, a paraphrase, or textbook stiffness.",
            ].joined(separator: "\n"),
            [
                "Internal process (keep this internal; show only the final fields):",
                "1. Identify the communicative intent / speech act (ask, request, soften, explain, push back, reassure, summarize, make a point).",
                "2. Ask: \"If a native English speaker wanted to express exactly this meaning here, in this register, what would they actually say?\" Write the best one as \"idiomatic\".",
                "3. Then give the FEW OTHER most-likely ways a native would say the same intent in this register — these become real alternatives, not padding.",
            ].joined(separator: "\n"),
            [
                "Rewrite rules:",
                "- If input is ENGLISH: revise into natural, idiomatic, conversational English a native would actually say; keep meaning, intent, politeness; minimal edits if already natural.",
                "- If input is CHINESE: treat it as INTENT to re-express in English; render the underlying request directly (我想说/我想提醒/我想问 -> say the point itself rather than leading with 'I want to say'); keep deadlines/actions/conditions/person refs explicit and precise (今天下午之前 -> 'by this afternoon', meaning the literal time); use ONE clear modal for polite requests (Could you..., Would it be possible to...) instead of stacking hedges; include only what the utterance implies, leaving greetings, names, apologies, sign-offs, and new facts out.",
            ].joined(separator: "\n"),
            [
                "Coaching (Simplified Chinese, concrete, 2-5 short bullets):",
                "- Why your version is more natural than the original; QUOTE the specific English snippets you changed; point at speech act, word choice, collocations, idioms, rhythm, register, what English leaves implicit.",
            ].joined(separator: "\n"),
            [
                "Thinking shift (Simplified Chinese, one tight paragraph):",
                "- Contrast 中式思维 vs 美式思维 behind THIS sentence, naming the pattern(s) actually at work; draw from: 1 话题优先->主谓宾SVO; 2 高语境先铺垫->低语境结论先行; 3 意合->形合(显性连接); 4 面子迂回委婉->一个情态动词+句法表礼貌不堆hedges; 5 大词/书面->短语动词/口语(discover->find out). Always name the specific pattern at work in THIS sentence.",
            ].joined(separator: "\n"),
            [
                "Context-use rules:",
                "- If target-app context is provided, treat it as a weak signal for register, insertion destination, terminology, and local coherence only.",
                "- Cursor text and selected text are background that explains the local document/topic; treat the spoken utterance as the only instruction and keep that surrounding text out of the answer.",
                "- Preserve user hotwords exactly when the utterance clearly refers to those terms; use a hotword only when the utterance actually calls for it.",
                "- Include only the names, facts, deadlines, citations, and content the utterance itself contains; carry nothing across from the document or surroundings.",
            ].joined(separator: "\n"),
            [
                "Output format:",
                "Return exactly one JSON object as raw text (no markdown fences) with this exact shape: {\"idiomatic\": string, \"alternatives\": string[], \"reasons\": string[], \"thinkingShift\": string}.",
                "\"idiomatic\": the final natural American English, plain text only.",
                "\"alternatives\": 2-3 OTHER natural ways a native would say it in the chosen register (the few most-likely phrasings — never an empty array).",
                "\"reasons\": 2-5 short Simplified Chinese bullets.",
                "\"thinkingShift\": Simplified Chinese, 中式 vs 美式 思维 specific to this sentence.",
            ].joined(separator: "\n"),
        ].joined(separator: "\n\n")

        let block = contextLines(context)
        let user = ([
            "Express this utterance the way a native American English speaker would say it (General American), then coach it.",
            "The source may be the user's rough/non-idiomatic English, or Chinese intent; do not mirror its wording.",
        ]
        + (block.isEmpty ? [] : ["", "Target context (weak signal only; do not invent facts from it):"] + block)
        + ["", "Utterance:", intent]).joined(separator: "\n")
        return (system, user)
    }

    /// 教练语域 directive (backend `coachRegisterDirective`).
    static func coachRegisterDirective(_ register: CoachRegister) -> String {
        switch register {
        case .neutral:
            return [
                "Register (中性 / neutral spoken): the clear, professional spoken English of a work call or cross-team chat — friendly but efficient, polished but not stiff.",
                "Still spoken and native: contractions are fine, light hedging is fine; just drop slang and very casual fillers. Keep preferring phrasal verbs and natural collocations over Latinate/textbook words.",
            ].joined(separator: "\n")
        case .formal:
            return [
                "Register (正式 / formal spoken): the way a native actually speaks in a formal meeting or to someone senior — fuller forms, fewer contractions, more complete sentences, polite framing.",
                "Formal as a native SAYS it out loud, NOT formal written prose: no Latinate translation-ese, no email boilerplate, no stiffness — what a poised native would actually say in the room.",
            ].joined(separator: "\n")
        case .academic:
            return [
                "Register (学术 / spoken academic): the spoken English of a research meeting, conference Q&A, or defense — precise, measured, hedged where scholars hedge (it seems, the data suggest, one possibility is), discipline-neutral.",
                "This is SPOKEN academic English you would say at a podium or in Q&A, NOT written paper prose: full sentences a person can deliver out loud, no citation syntax, no paragraph-essay clauses, never a translation.",
            ].joined(separator: "\n")
        case .casual:
            return [
                "Register (口语 / casual spoken): relaxed, conversational American English the way friends and labmates actually talk — contractions, easy phrasal verbs, light particles (kind of, I guess, honestly).",
                "This is the everyday spoken default; keep it natural and unforced, never textbook.",
            ].joined(separator: "\n")
        }
    }

    /// Budget-priority context block (backend `contextLines`). High → low priority; once the
    /// budget is reached the remaining lower-priority lines are dropped so a long selection can
    /// never crowd out the instruction.
    static func contextLines(_ context: ExpressionContext?) -> [String] {
        guard let context else { return [] }
        var candidates: [String] = []
        func push(_ value: String?, _ label: String, _ limit: Int) {
            guard let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return }
            candidates.append("\(label): \(String(v.prefix(limit)))")
        }
        push(context.selectedText, "Selected text near insertion point", 700)
        let hotwords = context.hotwords.map { String($0.prefix(80)) }.prefix(40)
        if !hotwords.isEmpty {
            candidates.append("User hotwords / exact terms: \(hotwords.joined(separator: ", "))")
        }
        push(context.textBeforeCursor, "Text before cursor", 700)
        push(context.textAfterCursor, "Text after cursor", 700)
        push(context.windowTitle, "Window title", 180)
        push(context.appName, "Target app", 120)
        push(context.bundleIdentifier, "Bundle ID", 120)

        var lines: [String] = []
        var total = 0
        for line in candidates {
            if !lines.isEmpty && total + line.count > contextTotalBudget { break }
            lines.append(line)
            total += line.count
        }
        return lines
    }
}
