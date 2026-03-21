---
name: en-to-zh-translation
description: >-
  Translates English technical documents into idiomatic Simplified Chinese.
  Use when the user asks to translate English to Chinese, translate to Chinese,
  translate to 中文, 翻译, 英译中, EN-to-ZH, or provides English text and
  requests a Chinese version.
---

# English-to-Chinese Technical Translation

## Model Selection

Prefer Gemini 2.5 Pro or Claude Opus for this task. If the current model is
neither, note the recommendation but proceed with the active model.

## Translation Prompt

When the user provides English text to translate, follow these rules exactly.

### Output Language

- Simplified Chinese (简体中文) by default.
- If the user explicitly requests Traditional Chinese (繁體中文), switch.

### What to Translate

- All prose, headings, captions, alt-text, and comments written in English.

### What NOT to Translate — Preserve Verbatim

- Code blocks, inline code, CLI commands, flags, file paths, URLs.
- Variable names, function names, class names, identifiers.
- Brand names and product names (e.g., Isaac Gym, PyTorch, Cursor).
- Acronyms that are universally used in English form (e.g., API, GPU, RL, PPO).

### Terminology Handling

- Use the established Chinese equivalent when one exists and is standard in
  the field. Examples:
  - reinforcement learning → 强化学习
  - policy gradient → 策略梯度
  - reward shaping → 奖励塑形
  - observation space → 观测空间
  - action space → 动作空间
  - neural network → 神经网络
  - hyperparameter → 超参数
  - inference → 推理
  - training loop → 训练循环
  - checkpoint → 检查点 (or keep "checkpoint" if context is code-adjacent)
- When no standard Chinese term exists, keep the English term and optionally
  parenthesize the Chinese gloss on first occurrence.

### Tone and Register

- Professional, clear, and concise — matching the register of a senior
  engineer writing internal documentation.
- Avoid overly literary or flowery phrasing.
- Avoid machine-translation artifacts: unnatural word order, redundant
  pronouns (他/她/它), or literal calques.

### Formatting

- Preserve the original Markdown structure: headings, lists, tables, code
  fences, links.
- Insert a half-width space between Chinese characters and adjacent
  Latin/digit characters (e.g., 使用 PyTorch 进行训练).
- Use Chinese punctuation for prose (，。；：！？""''）.
- Use half-width punctuation inside code or technical identifiers.

### Quality Self-Check

After translating, silently verify:
1. No English prose left untranslated (except items in the preserve list).
2. No code or identifiers accidentally translated.
3. Spacing rule between CJK and Latin characters is followed.
4. Chinese punctuation is used consistently in prose.
5. The translation reads naturally to a native Simplified Chinese speaker.

If any check fails, fix before presenting the result.

## Output Format

Return only the translated text in the same document structure as the input.
Do not include the original English alongside the translation unless the user
explicitly asks for a bilingual or side-by-side version.
