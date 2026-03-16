---
name: RL Reward Design Doc
overview: Create a Chinese markdown document detailing the multiplicative reward design for humanoid robot recovery from instability, covering hardware failure taxonomy, training strategy, and individual reward function specifications.
todos:
  - id: write-doc
    content: Write the full Chinese markdown document with all sections, mermaid diagrams, and LaTeX math formulas
    status: completed
isProject: false
---

# RL Reward Design Markdown Document

## Target File

Create a new file: `[reward_design_instability_recovery.md](reward_design_instability_recovery.md)` in `/Users/HanHu/Documents/Markdown/`

This document follows the style and conventions of the existing `[humanoid_robot_safety_controller_test_module.md](humanoid_robot_safety_controller_test_module.md)`.

## Document Structure

### 1. 设计目标 (Design Objective)

- Robot recovery from instability caused by: external disturbance, large disturbance, and hardware failure
- Brief statement that the simulation environment is handled by 张家明

### 2. 硬件故障分类 (Hardware Failure Taxonomy)

Two-level hierarchy:

**Four scenarios:**

- Scenario 1: Upper extremity failure (head, upper arms)
- Scenario 2: Right leg failure
- Scenario 3: Left leg failure
- Scenario 4: Hip joint motor failure

**Two broad categories:**

- Category 1 (above waist): head, arms, waist joint
- Category 2 (legs): lower extremities

Include a mermaid diagram showing the taxonomy tree.

Key constraint: if both legs fail, the controller cannot help -- out of scope.

### 3. 项目范围与优先级 (Project Scope and Priority)

- Controller focus: upper extremity failure + single leg failure
- Current priority: upper extremity first (tight timeline)
- Key insight: upper extremity motor failure modeled as external disturbance, so training for upper motor failure and external disturbance rejection share the same workflow -- the only difference is the number of controllable joints

### 4. 训练策略 (Training Strategy)

- Apply significant disturbance during walking gait until likely to fall
- Possibly continuous training from a pre-trained walking policy
- The robot must learn to stabilize itself before resuming velocity tracking

Include a mermaid flowchart showing: pre-trained walking policy -> apply disturbance -> instability -> stabilize -> resume tracking.

### 5. 奖励函数设计 (Reward Function Design)

#### 5.1 总体结构 -- 乘法奖励 (Overall Structure -- Multiplicative Reward)

$$R_{total} = R_{velocity} \times R_{stability}$$

Rationale: if either component is low, the total reward drops -- forcing the robot to satisfy both. When unstable, the robot should prioritize stability (give up velocity tracking) before resuming velocity tracking.

Placeholder note for a graph the user will insert later illustrating the combined behavior.

#### 5.2 基础奖励函数形式 (Base Reward Function Form)

$$r_i = \exp\left(-\frac{(x_i - x_{i,target})^2}{\sigma_i^2}\right)$$

- x_i: observed quantity
- x_{i,target}: designed target value
- \sigma_i: scaling parameter controlling sensitivity
- Peak value is 1.0 when x_i = x_{i,target}
- Expected learned performance: ~80-90% of peak
- Convergence can be assessed by comparing max achieved reward vs designed peak

#### 5.3 速度跟踪奖励 (Velocity Tracking Reward)

Components:

- Linear velocity x: \exp(-(v_x - v_{x,cmd})^2 / \sigma_{v_x}^2)
- Linear velocity y: \exp(-(v_y - v_{y,cmd})^2 / \sigma_{v_y}^2)
- Yaw rate: \exp(-(\dot{\psi} - \dot{\psi}*{cmd})^2 / \sigma*{\dot{\psi}}^2)

Combined: R_{velocity} = r_{v_x} \cdot r_{v_y} \cdot r_{\dot{\psi}}

Leave sigma values as parameters to be tuned (with placeholder values).

#### 5.4 稳定性奖励 (Stability Reward)

Components based on user selection:

- **Body orientation** (roll/pitch): \exp(-(\theta_{roll})^2/\sigma_{roll}^2) \cdot \exp(-(\theta_{pitch})^2/\sigma_{pitch}^2) with target = 0 (upright)
- **Angular velocity** of torso: \exp(-(\omega_{torso}^2)/\sigma_\omega^2) with target = 0 (no rotational disturbance)
- **Foot contact**: reward for maintaining expected contact pattern
- **ZMP**: \exp(-(d_{ZMP})^2/\sigma_{ZMP}^2) where d_{ZMP} is distance of ZMP from support polygon center

Combined: R_{stability} = r_{orientation} \cdot r_{\omega} \cdot r_{contact} \cdot r_{ZMP}

### 6. 收敛判据 (Convergence Criteria)

- Compare maximum achieved reward against the designed peak reward (product of all individual peaks = 1.0)
- Expected convergence range: 80-90% of peak
- Since the target is embedded in the exponential, the reference point for evaluation is well-defined

### 7. 备注与后续 (Notes and Next Steps)

- Placeholder for the user's combined behavior graph
- Note about simulation environment handled by 张家明
- Future extension to single-leg failure scenarios

