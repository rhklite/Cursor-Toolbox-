#!/usr/bin/env python3
"""
Hyperparameter config patcher for Python config files.

Patches by replacing existing key=value lines (regex) or injecting new override
lines into the correct inner class when the key doesn't already exist in the file.

Usage:
    hp_patcher.py <config_file> <assignments> [<class_map_json>]

    assignments:     semicolon-separated key=value pairs
                     e.g. "learning_rate=1e-4;entropy_coef=0.01"
    class_map_json:  JSON mapping param names to target inner class paths
                     e.g. '{"learning_rate": "algorithm"}'
                     Merges with (and overrides) DEFAULT_CLASS_MAP.
"""

import json
import re
import sys
from pathlib import Path

DEFAULT_CLASS_MAP = {
    # --- PPO algorithm params ---
    "learning_rate": "algorithm",
    "entropy_coef": "algorithm",
    "gamma": "algorithm",
    "lam": "algorithm",
    "clip_param": "algorithm",
    "num_learning_epochs": "algorithm",
    "num_mini_batches": "algorithm",
    "desired_kl": "algorithm",
    "max_grad_norm": "algorithm",
    "value_loss_coef": "algorithm",
    "use_clipped_value_loss": "algorithm",
    "schedule": "algorithm",
    # --- Symmetry config (nested inside algorithm) ---
    "mirror_loss_coeff": "algorithm.symmetry_cfg",
    "use_mirror_loss": "algorithm.symmetry_cfg",
    "use_data_augmentation": "algorithm.symmetry_cfg",
    "use_scaled_orthogonal_init": "algorithm.symmetry_cfg",
    "orthogonal_init_scale": "algorithm.symmetry_cfg",
    # --- Runner params ---
    "amp_task_reward_lerp": "runner",
    "max_iterations": "runner",
    "num_steps_per_env": "runner",
    "experiment_name": "runner",
    # --- Policy params ---
    "init_noise_std": "policy",
    # --- Env config params (Cfg class) ---
    "frame_stack": "env",
    "num_envs": "env",
    "num_single_obs": "env",
    "c_frame_stack": "env",
    # --- Reward params ---
    "tracking_sigma_lin_vel": "rewards",
    "soft_dof_vel_limit": "rewards",
    "soft_dof_pos_limit": "rewards",
    "tracking_sigma_torso_ang_vel_xy": "rewards",
    # --- Reward scales (nested inside rewards) ---
    "tracking_avg_ang_vel": "rewards.scales",
    "torque_limits": "rewards.scales",
    "stand_still": "rewards.scales",
    "foot_distance_limit": "rewards.scales",
    "hip_roll_and_ankle_pitch_torque_limits": "rewards.scales",
    "catwalk_thigh_roll": "rewards.scales",
    # --- Domain randomization ---
    "push_robots": "domain_rand",
    "max_push_vel_xy": "domain_rand",
    "randomize_base_mass": "domain_rand",
    "randomize_com_displacement": "domain_rand",
    "randomize_motor_strength": "domain_rand",
    "com_displacement_range": "domain_rand",
    "motor_strength_range": "domain_rand",
    # --- Commands ---
    "straight_prob": "commands.new_sample_methods",
    "backward_prob": "commands.new_sample_methods",
    "stand_prob": "commands.new_sample_methods",
    "turn_prob": "commands.new_sample_methods",
    # --- AMP env params ---
    "amp_task_reward_lerp": "runner",
}


def parse_assignments(raw: str):
    """Parse 'k1=v1;k2=v2' into [(k1,v1), (k2,v2)]."""
    pairs = []
    for part in raw.split(";"):
        part = part.strip()
        if not part:
            continue
        if "=" not in part:
            print(f"FATAL: invalid assignment (missing '='): {part}", file=sys.stderr)
            raise SystemExit(1)
        k, v = part.split("=", 1)
        k, v = k.strip(), v.strip()
        if not k or not v:
            print(f"FATAL: empty key or value in assignment: {part}", file=sys.stderr)
            raise SystemExit(1)
        pairs.append((k, v))
    return pairs


def try_regex_replace(text: str, key: str, value: str):
    """Replace the first occurrence of `key = ...` in text. Returns (new_text, success)."""
    pattern = re.compile(
        rf"(^[ \t]*{re.escape(key)}[ \t]*=[ \t]*).*$", re.MULTILINE
    )
    new_text, n = pattern.subn(lambda m: m.group(1) + value, text, count=1)
    return new_text, n > 0


def _indent_of(line: str) -> int:
    return len(line) - len(line.lstrip())


def find_class_block(lines, class_name, start=0, min_indent=-1):
    """
    Locate `class <class_name>` whose indentation > min_indent.

    Returns (class_line_idx, body_indent, last_body_line_idx) or None.
    """
    pat = re.compile(rf"^(\s*)class\s+{re.escape(class_name)}\b")

    for i in range(start, len(lines)):
        m = pat.match(lines[i])
        if not m:
            continue
        class_indent = len(m.group(1))
        if class_indent <= min_indent:
            continue

        colon_line = i
        if ":" not in lines[i]:
            for j in range(i + 1, len(lines)):
                if ":" in lines[j]:
                    colon_line = j
                    break

        body_indent = None
        for j in range(colon_line + 1, len(lines)):
            stripped = lines[j].strip()
            if stripped and not stripped.startswith("#"):
                body_indent = _indent_of(lines[j])
                break

        if body_indent is None:
            body_indent = class_indent + 4

        last_body = colon_line
        for j in range(colon_line + 1, len(lines)):
            stripped = lines[j].strip()
            if not stripped or stripped.startswith("#"):
                continue
            line_indent = _indent_of(lines[j])
            if line_indent <= class_indent:
                break
            last_body = j

        return (i, body_indent, last_body)

    return None


def inject_into_class(lines, class_path: str, key: str, value: str):
    """
    Insert `key = value` at the end of the specified class body.
    class_path is dot-separated, e.g. 'algorithm.symmetry_cfg'.
    """
    parts = class_path.split(".")
    search_start = 0
    min_indent = -1

    for depth, part in enumerate(parts):
        result = find_class_block(lines, part, search_start, min_indent)
        if result is None:
            avail = []
            cpat = re.compile(r"^\s*class\s+(\w+)")
            for ln in lines[search_start:]:
                cm = cpat.match(ln)
                if cm:
                    avail.append(cm.group(1))
            print(
                f"FATAL: cannot locate 'class {part}' "
                f"(path={class_path}, searching from line {search_start + 1}). "
                f"Classes visible from that point: {avail}",
                file=sys.stderr,
            )
            raise SystemExit(1)

        class_line, body_indent, last_body = result
        search_start = class_line + 1
        min_indent = _indent_of(lines[class_line])

    indent_str = " " * body_indent
    new_line = f"{indent_str}{key} = {value}\n"
    lines.insert(last_body + 1, new_line)
    return lines


def main():
    if len(sys.argv) < 3:
        print(
            "Usage: hp_patcher.py <config_file> <assignments> [<class_map_json>]",
            file=sys.stderr,
        )
        raise SystemExit(2)

    config_path = Path(sys.argv[1])
    assignments_str = sys.argv[2]
    class_map_json = sys.argv[3] if len(sys.argv) > 3 else "{}"

    if not config_path.exists():
        print(f"FATAL: config file not found: {config_path}", file=sys.stderr)
        raise SystemExit(1)

    class_map = dict(DEFAULT_CLASS_MAP)
    if class_map_json and class_map_json != "{}":
        try:
            class_map.update(json.loads(class_map_json))
        except json.JSONDecodeError as exc:
            print(f"FATAL: invalid class_map JSON: {exc}", file=sys.stderr)
            raise SystemExit(1)

    pairs = parse_assignments(assignments_str)
    if not pairs:
        print("FATAL: no valid assignments provided", file=sys.stderr)
        raise SystemExit(1)

    text = config_path.read_text(encoding="utf-8")
    replaced_keys = []
    injected_keys = []

    for key, value in pairs:
        new_text, did_replace = try_regex_replace(text, key, value)
        if did_replace:
            text = new_text
            replaced_keys.append(key)
            print(f"  [replace] {key} = {value}")
        else:
            target_class = class_map.get(key)
            if target_class is None:
                print(
                    f"FATAL: key '{key}' not found in file and has no class mapping. "
                    f"Either add it to the config file first, or include it in "
                    f"hp_class_map in your sweep payload.\n"
                    f"Known class mappings:\n{json.dumps(class_map, indent=2)}",
                    file=sys.stderr,
                )
                raise SystemExit(1)

            lines = text.splitlines(keepends=True)
            lines = inject_into_class(lines, target_class, key, value)
            text = "".join(lines)
            injected_keys.append(key)
            print(f"  [inject]  {key} = {value}  -> class {target_class}")

    config_path.write_text(text, encoding="utf-8")

    summary_parts = []
    if replaced_keys:
        summary_parts.append(f"replaced {len(replaced_keys)}")
    if injected_keys:
        summary_parts.append(f"injected {len(injected_keys)}")
    print(f"Patched {config_path.name}: {', '.join(summary_parts)} param(s)")


if __name__ == "__main__":
    main()
