#!/usr/bin/env python3
"""
Unit tests for the classification logic in verify_fuyao_jobs.sh.

Extracts the exact marker lists, regex patterns, and verdict mapping
from the inline Python snippets and runs them against synthetic inputs.
No SSH or network access required.
"""
import re
import sys


# ---------------------------------------------------------------------------
# Extracted logic: check_training_started  (verify_fuyao_jobs.sh lines 111-149)
# ---------------------------------------------------------------------------
TRAINING_MARKERS = [
    "num_learning_iterations",
    "Mean reward",
    "mean_reward",
    "AverageReturn",
    "ep_rew_mean",
    "reward_mean",
    "Episode reward",
    "value_loss",
    "policy_loss",
    "surrogate_loss",
    "Uploaded file to RTD",
]

TRAINING_PATTERNS = [
    r"model_\d+\.pt",
    r"Learning iteration \d+",
]

SETUP_MARKERS = [
    "auto register tasks",
    "tasks registered",
    "Loading extension module gymtorch",
    "pip install",
    "Loading AMP",
    "Loading motion",
    "ppo_runner.learn",
    "Starting training",
]

FAILED_MARKERS = [
    "Traceback",
    "RuntimeError",
    "CUDA out of memory",
    "OOM",
    "Segmentation fault",
    "core dumped",
    "ModuleNotFoundError",
    "ImportError",
    "FileNotFoundError",
]


def classify_log(log_text: str) -> str:
    has_training = any(m in log_text for m in TRAINING_MARKERS) or any(
        re.search(p, log_text) for p in TRAINING_PATTERNS
    )
    has_setup = any(m in log_text for m in SETUP_MARKERS)
    has_failure = any(m in log_text for m in FAILED_MARKERS)

    if has_failure and not has_training:
        return "failed_with_error"
    elif has_training:
        return "training_confirmed"
    elif has_setup:
        return "setup_in_progress"
    else:
        return "waiting_for_logs"


# ---------------------------------------------------------------------------
# Extracted logic: check_artifacts  (verify_fuyao_jobs.sh lines 159-188)
# ---------------------------------------------------------------------------
def extract_user(job_name: str):
    m = re.search(r"^[^-]+-[^-]+-(.+)$", job_name)
    return m.group(1) if m else None


def build_oss_url(user: str, job_name: str) -> str:
    return f"https://xrobot.xiaopeng.link/resource/xrobot-log/user-upload/fuyao/{user}/{job_name}/"


def classify_oss_response(response: str) -> str:
    if re.search(r"model_\d+\.pt", response):
        return "artifacts_found"
    return "no_artifacts"


# ---------------------------------------------------------------------------
# Extracted logic: verdict mapping  (verify_fuyao_jobs.sh lines 345-367)
# ---------------------------------------------------------------------------
def compute_verdict(
    training_status: str, artifact_status: str, job_status: str
) -> str:
    tr, ar, st = training_status, artifact_status, job_status
    if tr == "training_confirmed" and ar == "artifacts_found":
        return "TRAINING_WITH_ARTIFACTS"
    elif tr == "training_confirmed":
        return "TRAINING"
    elif tr == "setup_in_progress":
        return "SETUP"
    elif tr == "failed_with_error" or st == "failed":
        return "FAILED"
    elif st == "pending":
        return "PENDING"
    elif st in ("cancelled", "not_found"):
        return "GONE"
    else:
        return "UNKNOWN"


# ---------------------------------------------------------------------------
# Test runner
# ---------------------------------------------------------------------------
PASS_COUNT = 0
FAIL_COUNT = 0


def check(name: str, got, expected):
    global PASS_COUNT, FAIL_COUNT
    if got == expected:
        PASS_COUNT += 1
        print(f"  PASS  {name}")
    else:
        FAIL_COUNT += 1
        print(f"  FAIL  {name}  expected={expected!r}  got={got!r}")


def test_training_markers():
    print("\n=== Training marker classification ===")

    check(
        "DEMOTED: 'Starting training' alone",
        classify_log("Starting training with 1000 envs"),
        "setup_in_progress",
    )
    check(
        "DEMOTED: 'ppo_runner.learn' alone",
        classify_log("calling ppo_runner.learn()"),
        "setup_in_progress",
    )
    check(
        "DEMOTED: both demoted markers together",
        classify_log("Starting training\nppo_runner.learn called"),
        "setup_in_progress",
    )
    check(
        "Strict marker: 'Mean reward'",
        classify_log("Mean reward: 1.523"),
        "training_confirmed",
    )
    check(
        "Strict marker: 'value_loss'",
        classify_log("value_loss: 0.0032"),
        "training_confirmed",
    )
    check(
        "Strict marker: 'policy_loss'",
        classify_log("policy_loss: -0.012"),
        "training_confirmed",
    )
    check(
        "Strict marker: 'surrogate_loss'",
        classify_log("surrogate_loss: 0.041"),
        "training_confirmed",
    )
    check(
        "Strict marker: 'Uploaded file to RTD'",
        classify_log("Uploaded file to RTD"),
        "training_confirmed",
    )
    check(
        "Strict marker: 'num_learning_iterations'",
        classify_log("num_learning_iterations = 5000"),
        "training_confirmed",
    )
    check(
        "Regex pattern: model_500.pt",
        classify_log("Saving checkpoint model_500.pt"),
        "training_confirmed",
    )
    check(
        "Regex pattern: model_0.pt (iteration zero)",
        classify_log("model_0.pt saved"),
        "training_confirmed",
    )
    check(
        "Regex pattern: Learning iteration 100",
        classify_log("Learning iteration 100/5000"),
        "training_confirmed",
    )
    check(
        "Setup only: pip install",
        classify_log("pip install -e ."),
        "setup_in_progress",
    )
    check(
        "Setup only: Loading AMP",
        classify_log("Loading AMP data from disk"),
        "setup_in_progress",
    )
    check(
        "Failure without training",
        classify_log("Traceback (most recent call last):\nRuntimeError: CUDA error"),
        "failed_with_error",
    )
    check(
        "Failure + training markers -> training wins",
        classify_log("Mean reward: 2.1\nTraceback (most recent call last):"),
        "training_confirmed",
    )
    check(
        "Empty log text",
        classify_log(""),
        "waiting_for_logs",
    )
    check(
        "Unrecognised output",
        classify_log("some random log line with no markers"),
        "waiting_for_logs",
    )


def test_artifact_url():
    print("\n=== Artifact URL construction & response parsing ===")

    user = extract_user("bifrost-2025031212345678-huh8")
    check("User extraction: simple name", user, "huh8")
    check(
        "OSS URL: simple name",
        build_oss_url(user, "bifrost-2025031212345678-huh8"),
        "https://xrobot.xiaopeng.link/resource/xrobot-log/user-upload/fuyao/huh8/bifrost-2025031212345678-huh8/",
    )

    user2 = extract_user("bifrost-2025031212345678-wang-b33")
    check("User extraction: hyphenated name", user2, "wang-b33")
    check(
        "OSS URL: hyphenated name",
        build_oss_url(user2, "bifrost-2025031212345678-wang-b33"),
        "https://xrobot.xiaopeng.link/resource/xrobot-log/user-upload/fuyao/wang-b33/bifrost-2025031212345678-wang-b33/",
    )

    check(
        "Invalid job name (no hyphens) -> None user",
        extract_user("nohyphens"),
        None,
    )
    check(
        "Invalid job name (one hyphen) -> None user",
        extract_user("only-onehyphen"),
        None,
    )

    check(
        "OSS response with model file",
        classify_oss_response('<a href="model_500.pt">model_500.pt</a>'),
        "artifacts_found",
    )
    check(
        "OSS response with multiple models",
        classify_oss_response("model_100.pt\nmodel_200.pt\nmodel_300.pt"),
        "artifacts_found",
    )
    check(
        "OSS response without .pt files",
        classify_oss_response("<html><body>metadata.json</body></html>"),
        "no_artifacts",
    )
    check(
        "Empty OSS response",
        classify_oss_response(""),
        "no_artifacts",
    )


def test_verdict_mapping():
    print("\n=== Verdict mapping ===")

    check(
        "training + artifacts_found",
        compute_verdict("training_confirmed", "artifacts_found", "running"),
        "TRAINING_WITH_ARTIFACTS",
    )
    check(
        "training + unchecked",
        compute_verdict("training_confirmed", "unchecked", "running"),
        "TRAINING",
    )
    check(
        "training + artifacts_check_failed",
        compute_verdict("training_confirmed", "artifacts_check_failed", "running"),
        "TRAINING",
    )
    check(
        "training + no_artifacts",
        compute_verdict("training_confirmed", "no_artifacts", "running"),
        "TRAINING",
    )
    check(
        "setup_in_progress",
        compute_verdict("setup_in_progress", "unchecked", "running"),
        "SETUP",
    )
    check(
        "failed_with_error from training check",
        compute_verdict("failed_with_error", "unchecked", "running"),
        "FAILED",
    )
    check(
        "job status failed",
        compute_verdict("unknown", "unchecked", "failed"),
        "FAILED",
    )
    check(
        "job status pending",
        compute_verdict("unknown", "unchecked", "pending"),
        "PENDING",
    )
    check(
        "job status cancelled",
        compute_verdict("unknown", "unchecked", "cancelled"),
        "GONE",
    )
    check(
        "job status not_found",
        compute_verdict("unknown", "unchecked", "not_found"),
        "GONE",
    )
    check(
        "all unknown",
        compute_verdict("unknown", "unchecked", "unknown"),
        "UNKNOWN",
    )


def test_invalid_job_name_gives_artifacts_check_failed():
    """The bash function returns artifacts_check_failed when user can't be parsed."""
    print("\n=== Invalid job name -> artifacts_check_failed ===")
    user = extract_user("nohyphens")
    result = "artifacts_check_failed" if user is None else "ok"
    check("Invalid job name triggers artifacts_check_failed path", result, "artifacts_check_failed")


if __name__ == "__main__":
    test_training_markers()
    test_artifact_url()
    test_verdict_mapping()
    test_invalid_job_name_gives_artifacts_check_failed()

    print(f"\n{'='*50}")
    print(f"Results: {PASS_COUNT} passed, {FAIL_COUNT} failed")
    if FAIL_COUNT > 0:
        print("SOME TESTS FAILED")
        sys.exit(1)
    else:
        print("ALL TESTS PASSED")
        sys.exit(0)
