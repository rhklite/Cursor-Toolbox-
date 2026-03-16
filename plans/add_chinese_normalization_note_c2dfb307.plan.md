---
name: Add Chinese normalization note
overview: Add a concise Chinese subsection under 5.0.1 to capture the final normalization logic from our discussion, without equations-heavy detail.
todos:
  - id: locate-insert-point
    content: Confirm insertion point under 5.0.1 before 5.0.2
    status: completed
  - id: draft-chinese-bullets
    content: Draft concise Chinese bullet points for normalization meaning
    status: completed
  - id: consistency-pass
    content: Ensure wording aligns with x_target/sigma semantics in 5.0.2
    status: completed
isProject: false
---

# 在 5.0.1 下新增中文说明

## 目标

在 [reward_design_instability_recovery.md](/Users/HanHu/Documents/Markdown/reward_design_instability_recovery.md) 的 `5.0.1 乘法耦合` 下，新增一个简洁中文小节，解释“速度误差归一化后的无量纲值代表什么”这一最终结论。

## 修改范围

- 仅修改一个文件：
  - [reward_design_instability_recovery.md](/Users/HanHu/Documents/Markdown/reward_design_instability_recovery.md)
- 插入位置：`5.0.1 乘法耦合` 末尾（在 `判据输出` 后、`5.0.2` 前）。

## 内容组织（中文、简洁）

- 使用 3-5 条 bullet points，避免冗长解释。
- 覆盖以下逻辑：
  - 先按各维参考尺度归一化，再合并误差；
  - 归一化值是“相对容忍度的偏差倍数”；
  - 数值直觉：`0` 表示对齐目标，`1` 表示达到参考误差，`>1` 表示超出容忍范围；
  - 该表示可避免不同维度单位混杂导致的权重失衡。
- 与现有 `5.0.2` 的基础奖励函数口径保持一致（`x_target`、`sigma` 语义一致）。

## 验证

- 检查标题层级与编号不变。
- 检查新增段落为纯中文简明说明，不引入不必要术语。

