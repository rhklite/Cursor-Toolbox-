---
name: reward-design-analyzer
description: Analyzes RL reward design for a registered task by tracing config inheritance, categorizing all reward terms, ranking importance, identifying external disturbances, and producing a Markdown report with tuning suggestions. Use when the user asks to analyze rewards, understand reward design, trace reward configs, tune rewards, or wants a reward breakdown for a task in the motion_rl / humanoid-gym codebase.
---

# Reward Design Analyzer

Produce a comprehensive Markdown report of the reward design for a given registered task in the humanoid-gym codebase.

## Inputs

Gather from the user (or infer from context):

1. **Task name or line number** in `humanoid-gym/humanoid/envs/__init__.py`
2. **Tuning objective** — what behavior they want to achieve or improve (e.g., "prioritize stability over velocity tracking")
3. **Output location** — where to save the Markdown report (default: `~/Downloads/`)

## Workflow

### Step 1 — Identify the task registration

Read `humanoid-gym/humanoid/envs/__init__.py` at the specified line. Extract:

- Task string name
- Env class (e.g., `R01V12AMPEnv`)
- Env config class (e.g., `R01V12SAAMPWith4DoFArmsAndHeadFullScenesCfg`)
- PPO config class

### Step 2 — Trace the reward config inheritance chain

Starting from the leaf config class:

1. Find the file where the config class is defined (follow the import).
2. Read the `rewards` class and its `scales` subclass.
3. Identify the parent class of `rewards` (e.g., `R01V12AMPWith4DoFArmsCfg.rewards`).
4. Recurse up the chain until reaching the base config (`R01AMPCfg` or `LeggedRobotCfg`).
5. At each level, record all reward parameters and scale overrides.
6. Compute the **final effective values** after all inheritance is applied.

### Step 3 — Find all reward computation methods

Starting from the env class:

1. Read the env file and find all `_reward_*` methods.
2. Trace the env inheritance chain (e.g., `R01V12AMPEnv` -> `R01AMPEnv` -> `LeggedRobot`).
3. For each `_reward_*` method, record: name, file, formula, purpose.
4. Note which methods are overridden vs inherited.

### Step 4 — Find the AMP/task reward mixing

Look for `amp_task_reward_lerp` in the PPO config. Record:

- The lerp value (or schedule if it's a dict)
- The formula: `total = (1 - lerp) * amp_reward + lerp * task_reward`

### Step 5 — Find external disturbances

Search the `domain_rand` config class and env code for:

- Push forces (`push_robots`, `max_push_vel_xy`, `max_push_ang_vel`, intervals)
- Joint torque perturbations
- Domain randomization (mass, COM, motor strength, Kp/Kd, friction, restitution)
- IMU offset randomization
- Torque delay
- DOF position/velocity perturbations
- Any other perturbation mechanisms

For each, record: enabled/disabled, parameter values, when applied.

### Step 6 — Find command distribution

Read the `commands.new_sample_methods` class for `stand_prob`, `straight_prob`, `turn_prob`, `backward_prob` and velocity ranges.

### Step 7 — Write the Markdown report

Produce a single Markdown file with these sections:

1. **File Map** — table of all relevant files
2. **Config Inheritance Chain** — Mermaid diagram
3. **Total Reward Architecture** — AMP vs task split with Mermaid diagram
4. **Reward Terms — Full Breakdown** — organized into categories:
   - Category A: Velocity Tracking (positive rewards)
   - Category B: Motion Smoothness (negative penalties)
   - Category C: Safety / Joint Limits (negative penalties)
   - Category D: Disabled (scale = 0, available in code)
5. **Relative Importance Ranking** — table + Mermaid pie chart
6. **External Disturbances** — active/inactive disturbances with Mermaid diagram
7. **Command Distribution** — probabilities table
8. **Tuning Suggestions** — specific to the user's stated objective, with:
   - Which rewards to enable/disable and suggested value ranges
   - Which parameters to adjust (sigma, probabilities, AMP lerp)
   - Recommended starting config (copy-pasteable Python)
   - Iterative tuning order (prioritized steps)

## Output format

Single Markdown file with:

- Header sections (`##`) for each topic
- Tables for structured data
- Mermaid diagrams for inheritance chains, architecture, disturbance timing, and reward distribution
- Copy-pasteable Python config snippets in tuning suggestions
- No emojis unless the user requests them

## Key files to search

```
humanoid-gym/humanoid/envs/__init__.py          # task registration
humanoid-gym/humanoid/envs/r01_amp/             # config + env files
humanoid-gym/humanoid/envs/base/legged_robot.py # reward dispatch, disturbances
```

## Notes

- Reward scales are multiplied by `dt` at runtime — report the pre-dt config values.
- Only rewards with non-zero scales are active; `_prepare_reward_function()` removes zero-scale entries.
- The AMP discriminator reward is implicit and not defined in the config scales — call it out as Rank 0.
- When suggesting tuning, always check whether a reward method already exists in the env code before suggesting new code.
