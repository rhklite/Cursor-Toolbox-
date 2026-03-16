---
name: Full XML integration test
overview: Rewrite `TestFullDashboardXML` in `test_plotjuggler_xml_signals.py` to comprehensively validate `r01_plotjuggler_full.xml` — covering reward curves against `R01PlusAMPTeleopCfg`, computed math equation source paths, structural signal paths, and a live container UDP capture.
todos:
  - id: reward-validation
    content: Add `test_reward_curves_match_config` -- validate all 19 reward names from XML exist in `R01PlusAMPTeleopCfg` scales
    status: completed
  - id: math-equation-validation
    content: Add `_extract_math_equation_sources` and `test_computed_curve_sources_are_valid` for the 5 computed curves
    status: completed
  - id: udp-streamer-test
    content: Add `test_udp_streamer_enabled` to `TestFullDashboardXML`
    status: completed
  - id: container-validation
    content: Run inline config introspection in Isaac Gym container to confirm reward names and dataclass fields
    status: completed
isProject: false
---

# Full XML Integration Test

## Target

[`r01_plotjuggler_full.xml`](humanoid-gym/datasets/tool/config/r01_plotjuggler_full.xml) -- the only file under test. UDP config is already present (line 373: `<previouslyLoaded_Streamer name="UDP Server"/>`).

## Current gap

The existing `TestFullDashboardXML` class in [`test_plotjuggler_xml_signals.py`](humanoid-gym/tests/test_plotjuggler_xml_signals.py) has two tests:
- `test_xml_exists` -- trivial
- `test_structural_curves_are_valid` -- skips all 19 reward curves and all 5 computed curves (`ERR_*`, `REF_*`) via `_is_dynamic_reward_path()` and `COMPUTED_CURVE_RE`

That means **38 of 66 total curve references are untested** (19 reward names x 2 prefixes + episode_sums + computed).

## Step 1: Validate reward curves against task config

The XML's reward names match [`R01PlusAMPTeleopCfg`](humanoid-gym/humanoid/envs/r01_amp/r01_plus_amp_config_teleop.py). Its `scales` class inherits `R01PlusAMPWith4DoFArmsCfg.rewards.scales` and adds `tracking_waist_yaw` (0.5) and `waist_soft_limit` (-1000.0). The base 17 rewards come from [`R01AMPCfg.rewards.scales`](humanoid-gym/humanoid/envs/r01_amp/r01_amp_config.py) (line 287).

Add a hardcoded `EXPECTED_REWARD_NAMES` set with all 19 names to `test_plotjuggler_xml_signals.py`. Add a new test `test_reward_curves_match_config` that:
1. Extracts all curve names matching `/learning/rl_extra_info/raw_rewards/<name>`, `/learning/rl_extra_info/scaled_rewards/<name>`, and `/learning/episode_sums/<name>`
2. Collects the unique `<name>` suffixes
3. Asserts every extracted reward name is in `EXPECTED_REWARD_NAMES`
4. Asserts the three groups (raw, scaled, episode_sums) use the same reward name set

## Step 2: Validate computed math equation sources

The XML has 5 `<customMathEquations>` snippets (`REF_0.0`, `REF_1.0`, `ERR_vel_x`, `ERR_vel_y`, `ERR_vel_yaw`). Each has a `<linked_source>` and optional `$$path$$` references in `<equation>`.

Add `_extract_math_equation_sources(xml_path)` that parses `<snippet>` elements to collect:
- The `<linked_source>` text
- Any `$$...$$`-delimited paths from the `<equation>` text

Add a test `test_computed_curve_sources_are_valid` that asserts every collected source path exists in the structural signal path set built by `_build_all_valid_paths()`.

The 7 source paths to validate:

| Snippet | linked_source | equation refs |
|---------|--------------|---------------|
| `REF_0.0` | `/learning/rl_extra_info/total_reward` | -- |
| `REF_1.0` | `/learning/rl_extra_info/total_reward` | -- |
| `ERR_vel_x` | `/learning/rl_obs_unscaled/cmd/root_lin_vel_x` | `/learning/rl_extra_info/pelvis_lin_vel/lin_vel_x` |
| `ERR_vel_y` | `/learning/rl_obs_unscaled/cmd/root_lin_vel_y` | `/learning/rl_extra_info/pelvis_lin_vel/lin_vel_y` |
| `ERR_vel_yaw` | `/learning/rl_obs_unscaled/cmd/root_ang_vel_yaw` | `/learning/rl_extra_info/base_avg_vel/ang_vel_z` |

## Step 3: Add UDP streamer test

Add `test_udp_streamer_enabled` to `TestFullDashboardXML` (same pattern as `TestLimitInspectXML`).

## Step 4: Live container validation

Run an inline Python script in the Isaac Gym container via the skill runner that:
1. Imports `R01PlusAMPTeleopCfg` and verifies the reward scale keys contain all 19 reward names
2. Confirms the `RLExtraInfo` dataclass has the `dof_pos_limits` field
3. Verifies the `customMathEquations` source paths structurally resolve

This does not require a GPU or checkpoint -- it only introspects config classes and dataclass fields.

## Files changed

- [`humanoid-gym/tests/test_plotjuggler_xml_signals.py`](humanoid-gym/tests/test_plotjuggler_xml_signals.py) -- add reward validation, math equation source validation, UDP streamer test
