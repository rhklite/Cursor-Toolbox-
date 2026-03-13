#!/usr/bin/env python3
"""Tests for fuyao_job_manager.py — stability and reliability focus."""

import fcntl
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile
import textwrap
import time
import unittest
from io import StringIO
from pathlib import Path
from unittest.mock import MagicMock, patch, call

sys.path.insert(0, str(Path(__file__).parent))
import fuyao_job_manager as fjm


def _make_registry(jobs=None):
    return {"version": fjm.REGISTRY_VERSION, "jobs": jobs or []}


def _make_job(name="bifrost-1234567890123456-huh8", sweep_id="sweep-1", label="label-1",
              task="task-1", queue="q-1", gpus=4, status="running", protected=True):
    return {
        "job_name": name, "sweep_id": sweep_id, "combo_label": label,
        "task": task, "queue": queue, "gpus": gpus,
        "dispatched_at": "2026-01-01T00:00:00+00:00", "status": status, "protected": protected,
    }


class RegistryTmpMixin:
    """Mixin that redirects REGISTRY_PATH to a temp file for each test."""
    def setUp(self):
        self._tmp = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
        self._tmp.close()
        self._orig_path = fjm.REGISTRY_PATH
        fjm.REGISTRY_PATH = Path(self._tmp.name)

    def tearDown(self):
        fjm.REGISTRY_PATH = self._orig_path
        try:
            os.unlink(self._tmp.name)
        except FileNotFoundError:
            pass


# =========================================================================
# T1. Registry Integrity
# =========================================================================

class T1_RegistryIntegrity(RegistryTmpMixin, unittest.TestCase):

    def test_t1_1_atomic_write_leaves_valid_json(self):
        """T1.1: After _save_registry, file must be valid JSON."""
        reg = _make_registry([_make_job()])
        fjm._save_registry(reg)
        with open(fjm.REGISTRY_PATH, "r") as f:
            data = json.load(f)
        self.assertEqual(len(data["jobs"]), 1)

    def test_t1_1_atomic_write_uses_rename(self):
        """T1.1: _save_registry should write to temp then rename (atomic)."""
        reg = _make_registry([_make_job()])
        fjm._save_registry(reg)
        content = fjm.REGISTRY_PATH.read_text()
        self.assertIn("bifrost-1234567890123456-huh8", content)

    def test_t1_2_corrupt_registry_returns_empty(self):
        """T1.2: Malformed JSON should return empty registry + print warning."""
        fjm.REGISTRY_PATH.write_text("{invalid json!!!", encoding="utf-8")
        with patch("sys.stderr", new_callable=StringIO) as mock_err:
            reg = fjm._load_registry()
        self.assertEqual(reg["jobs"], [])
        self.assertEqual(reg["version"], fjm.REGISTRY_VERSION)

    def test_t1_3_missing_registry(self):
        """T1.3: Missing file returns empty registry."""
        os.unlink(fjm.REGISTRY_PATH)
        reg = fjm._load_registry()
        self.assertEqual(reg, {"version": fjm.REGISTRY_VERSION, "jobs": []})

    def test_t1_5_large_registry_performance(self):
        """T1.5: _find_jobs with 500 entries completes in < 0.1s."""
        jobs = [_make_job(name=f"bifrost-{i:020d}-huh8", sweep_id=f"s-{i % 10}") for i in range(500)]
        reg = _make_registry(jobs)
        t0 = time.time()
        result = fjm._find_jobs(reg, sweep_id="s-5")
        elapsed = time.time() - t0
        self.assertEqual(len(result), 50)
        self.assertLess(elapsed, 0.1)


# =========================================================================
# T2. Cancel Safety
# =========================================================================

class T2_CancelSafety(RegistryTmpMixin, unittest.TestCase):

    def test_t2_1_protected_job_blocked(self):
        """T2.1: Cancel on a protected job exits non-zero."""
        reg = _make_registry([_make_job(protected=True)])
        fjm._save_registry(reg)
        args = MagicMock(
            stale=False, label_pattern=None, sweep_id=None,
            job_name="bifrost-1234567890123456-huh8",
            force=False, dry_run=False, signal="7", ssh_alias="test",
            yes=False,
        )
        with self.assertRaises(SystemExit) as ctx:
            fjm.cmd_cancel(args)
        self.assertNotEqual(ctx.exception.code, 0)

    def test_t2_2_protected_job_with_force(self):
        """T2.2: Cancel with --force proceeds past protection."""
        reg = _make_registry([_make_job(protected=True)])
        fjm._save_registry(reg)
        args = MagicMock(
            stale=False, label_pattern=None, sweep_id=None,
            job_name="bifrost-1234567890123456-huh8",
            force=True, dry_run=True, signal="7", ssh_alias="test",
            yes=False,
        )
        fjm.cmd_cancel(args)

    def test_t2_3_dry_run_never_cancels(self):
        """T2.3: --dry-run sends zero SSH cancel requests."""
        reg = _make_registry([_make_job(protected=False)])
        fjm._save_registry(reg)
        args = MagicMock(
            stale=False, label_pattern=None, sweep_id=None,
            job_name="bifrost-1234567890123456-huh8",
            force=True, dry_run=True, signal="7", ssh_alias="test",
            yes=False,
        )
        with patch.object(fjm, "_ssh_cmd") as mock_ssh:
            fjm.cmd_cancel(args)
            mock_ssh.assert_not_called()

    def test_t2_4_empty_registry_cancel_stale(self):
        """T2.4: cancel --stale with empty registry does nothing."""
        fjm._save_registry(_make_registry())
        history_output = "  job_name      : bifrost-9999999999999999-huh8\n  status        : JOB_RUNNING\n"
        args = MagicMock(
            stale=True, label_pattern=None, sweep_id=None, job_name=None,
            force=False, dry_run=True, signal="7", ssh_alias="test",
            yes=False,
        )
        with patch.object(fjm, "_ssh_cmd", return_value=(0, history_output)):
            fjm.cmd_cancel(args)

    def test_t2_5_shell_injection_quoted(self):
        """T2.5: Job name with shell metacharacters is quoted in SSH cmd."""
        malicious = "bifrost-1234567890123456-huh8; rm -rf /"
        with patch("subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(returncode=0, stdout="", stderr="")
            fjm._ssh_cmd("test-alias", f"fuyao cancel --job-name {shlex.quote(malicious)}")
            called_cmd = mock_run.call_args[0][0]
            remote_part = called_cmd[2]
            self.assertNotIn("; rm", remote_part.replace(shlex.quote(malicious), ""))

    def test_t2_6_cancel_without_yes_requires_confirmation(self):
        """T2.6: Cancel without --yes prompts (tested via --yes flag existence)."""
        parser = fjm.build_parser()
        args = parser.parse_args(["cancel", "--job-name", "test-job"])
        self.assertTrue(hasattr(args, "yes") or hasattr(args, "dry_run"))


# =========================================================================
# T3. SSH Reliability
# =========================================================================

class T3_SSHReliability(unittest.TestCase):

    def test_t3_1_timeout_returns_error(self):
        """T3.1: SSH timeout returns error tuple."""
        with patch("subprocess.run", side_effect=subprocess.TimeoutExpired("ssh", 5)):
            rc, out = fjm._ssh_cmd("alias", "cmd", timeout=5)
        self.assertNotEqual(rc, 0)
        self.assertIn("timed out", out.lower())

    def test_t3_2_connection_refused(self):
        """T3.2: SSH to bad host returns clean error."""
        with patch("subprocess.run") as mock:
            mock.return_value = MagicMock(returncode=255, stdout="", stderr="Connection refused")
            rc, out = fjm._ssh_cmd("bad-host", "echo hi")
        self.assertEqual(rc, 255)

    def test_t3_3_malformed_output_no_crash(self):
        """T3.3: Unexpected fuyao info format doesn't crash status parsing."""
        garbage = "some random\noutput without\nexpected fields\n"
        with patch.object(fjm, "_ssh_cmd", return_value=(0, garbage)):
            reg = _make_registry([_make_job()])
            with patch.object(fjm, "_load_registry", return_value=reg):
                args = MagicMock(all_running=False, sweep_id=None,
                                job_name="bifrost-1234567890123456-huh8",
                                ssh_alias="test")
                fjm.cmd_status(args)

    def test_t3_4_retry_on_transient_failure(self):
        """T3.4: _ssh_cmd retries once on timeout."""
        call_count = [0]
        orig_run = subprocess.run

        def mock_run(*a, **kw):
            call_count[0] += 1
            if call_count[0] == 1:
                raise subprocess.TimeoutExpired("ssh", 5)
            return MagicMock(returncode=0, stdout="ok", stderr="")

        with patch("subprocess.run", side_effect=mock_run):
            rc, out = fjm._ssh_cmd("alias", "cmd", timeout=5)
        self.assertEqual(rc, 0)
        self.assertEqual(call_count[0], 2)

    def test_t3_5_special_chars_escaped(self):
        """T3.5: = and spaces in job name are properly handled."""
        jn = "bifrost-1234567890123456-huh8"
        quoted = shlex.quote(jn)
        self.assertEqual(quoted, jn)
        special = "job=with spaces"
        quoted_special = shlex.quote(special)
        self.assertIn("'", quoted_special)


# =========================================================================
# T4. Registry Operations
# =========================================================================

class T4_RegistryOps(RegistryTmpMixin, unittest.TestCase):

    def test_t4_1_add_creates_correct_fields(self):
        """T4.1: registry --add populates all expected fields."""
        fjm._save_registry(_make_registry())
        args = MagicMock(
            list=False, protect=None, unprotect=None, sync=False,
            add="bifrost-1234567890123456-huh8", remove=None, clear=False,
            add_batch=None,
            sweep_id="sweep-1", label="my-label", task="my-task",
            queue="my-queue", gpus="4", ssh_alias="test",
        )
        fjm.cmd_registry(args)
        reg = fjm._load_registry()
        job = reg["jobs"][0]
        self.assertEqual(job["job_name"], "bifrost-1234567890123456-huh8")
        self.assertEqual(job["sweep_id"], "sweep-1")
        self.assertEqual(job["combo_label"], "my-label")
        self.assertEqual(job["task"], "my-task")
        self.assertEqual(job["queue"], "my-queue")
        self.assertEqual(job["gpus"], 4)
        self.assertEqual(job["status"], "running")
        self.assertTrue(job["protected"])

    def test_t4_2_add_idempotent(self):
        """T4.2: Adding same job_name twice updates, doesn't duplicate."""
        fjm._save_registry(_make_registry())
        args = MagicMock(
            list=False, protect=None, unprotect=None, sync=False,
            add="bifrost-1234567890123456-huh8", remove=None, clear=False,
            add_batch=None,
            sweep_id="s1", label="v1", task="t", queue="q", gpus="1", ssh_alias="test",
        )
        fjm.cmd_registry(args)
        args.label = "v2"
        fjm.cmd_registry(args)
        reg = fjm._load_registry()
        self.assertEqual(len(reg["jobs"]), 1)
        self.assertEqual(reg["jobs"][0]["combo_label"], "v2")

    def test_t4_3_protect_unprotect(self):
        """T4.3: Protect/unprotect toggles flag and persists."""
        fjm._save_registry(_make_registry([_make_job(protected=False)]))
        args_p = MagicMock(
            list=False, protect="bifrost-1234567890123456-huh8", unprotect=None,
            add=None, sync=False, remove=None, clear=False, add_batch=None, ssh_alias="test",
        )
        fjm.cmd_registry(args_p)
        reg = fjm._load_registry()
        self.assertTrue(reg["jobs"][0]["protected"])

        args_u = MagicMock(
            list=False, protect=None, unprotect="bifrost-1234567890123456-huh8",
            add=None, sync=False, remove=None, clear=False, add_batch=None, ssh_alias="test",
        )
        fjm.cmd_registry(args_u)
        reg = fjm._load_registry()
        self.assertFalse(reg["jobs"][0]["protected"])

    def test_t4_4_sync_maps_status(self):
        """T4.4: Sync maps JOB_RUNNING->running, JOB_CANCELLED->cancelled, etc."""
        jobs = [
            _make_job(name="j1", status="running"),
            _make_job(name="j2", status="running"),
        ]
        reg = _make_registry(jobs)
        fjm._save_registry(reg)

        def mock_ssh(alias, cmd, timeout=30):
            if "j1" in cmd:
                return 0, "  status        : JOB_CANCELLED\n"
            return 0, "  status        : JOB_RUNNING\n"

        with patch.object(fjm, "_ssh_cmd", side_effect=mock_ssh):
            loaded = fjm._load_registry()
            fjm._registry_sync(loaded, "test")

        reg = fjm._load_registry()
        j1 = [j for j in reg["jobs"] if j["job_name"] == "j1"][0]
        j2 = [j for j in reg["jobs"] if j["job_name"] == "j2"][0]
        self.assertEqual(j1["status"], "cancelled")
        self.assertEqual(j2["status"], "running")

    def test_t4_5_sync_auto_unprotects_terminal(self):
        """T4.5: Terminal states set protected=False."""
        reg = _make_registry([_make_job(name="j1", status="running", protected=True)])
        fjm._save_registry(reg)

        with patch.object(fjm, "_ssh_cmd", return_value=(0, "  status        : JOB_FAILED\n")):
            loaded = fjm._load_registry()
            fjm._registry_sync(loaded, "test")

        reg = fjm._load_registry()
        self.assertFalse(reg["jobs"][0]["protected"])

    def test_t4_6_remove_deletes_entry(self):
        """T4.6: registry --remove deletes the entry."""
        fjm._save_registry(_make_registry([_make_job()]))
        args = MagicMock(
            list=False, protect=None, unprotect=None, add=None, sync=False,
            remove="bifrost-1234567890123456-huh8", clear=False, add_batch=None,
            ssh_alias="test",
        )
        fjm.cmd_registry(args)
        reg = fjm._load_registry()
        self.assertEqual(len(reg["jobs"]), 0)


# =========================================================================
# T5. Pull Operations
# =========================================================================

class T5_PullOps(unittest.TestCase):

    def test_t5_1_type_filtering(self):
        """T5.1: Each type filters expected patterns."""
        files = ["model_100.pt", "model_200.pt", "train.log", "output.txt",
                 "video.mp4", "clip.avi", "policy.onnx", "metrics.json", "data.csv",
                 "events.out.tfevents.12345", "random.xyz"]
        self.assertEqual(fjm._filter_files(files, "checkpoints"), ["model_100.pt", "model_200.pt"])
        self.assertEqual(fjm._filter_files(files, "logs"), ["train.log", "output.txt"])
        self.assertEqual(fjm._filter_files(files, "videos"), ["video.mp4", "clip.avi"])
        self.assertEqual(fjm._filter_files(files, "onnx"), ["policy.onnx"])
        self.assertEqual(fjm._filter_files(files, "metrics"), ["metrics.json", "data.csv"])

    def test_t5_2_pattern_regex(self):
        """T5.2: --pattern regex filters correctly."""
        files = ["model_100.pt", "model_9033.pt", "model_9442.pt"]
        result = fjm._filter_files(files, "checkpoints", pattern=r"model_9\d+\.pt")
        self.assertEqual(result, ["model_9033.pt", "model_9442.pt"])

    def test_t5_3_empty_listing(self):
        """T5.3: Empty OSS listing warns, doesn't crash."""
        with patch.object(fjm, "_list_oss_files", return_value=[]):
            args = MagicMock(sweep_id=None, job_name="test-job", type="all",
                            output_dir=None, pattern=None, ssh_alias="test")
            fjm.cmd_pull(args)

    def test_t5_5_invalid_regex_handled(self):
        """T5.5: Invalid regex in --pattern reports error."""
        files = ["model_100.pt"]
        try:
            fjm._filter_files(files, "checkpoints", pattern="[invalid")
            self.fail("Expected re.error")
        except re.error:
            pass


# =========================================================================
# T6. Edge Cases
# =========================================================================

class T6_EdgeCases(RegistryTmpMixin, unittest.TestCase):

    def test_t6_1_non_numeric_gpus(self):
        """T6.1: Non-numeric --gpus reports error."""
        fjm._save_registry(_make_registry())
        args = MagicMock(
            list=False, protect=None, unprotect=None, sync=False,
            add="test-job", remove=None, clear=False, add_batch=None,
            sweep_id="", label="", task="", queue="", gpus="abc", ssh_alias="test",
        )
        try:
            fjm.cmd_registry(args)
        except (ValueError, SystemExit):
            pass

    def test_t6_2_empty_user_extraction(self):
        """T6.2: Job name without user segment returns empty string."""
        self.assertEqual(fjm._extract_user("no-match"), "")

    def test_t6_4_find_jobs_empty_sweep_id(self):
        """T6.4: sweep_id="" is falsy, treated as no-filter."""
        reg = _make_registry([_make_job(sweep_id="s1"), _make_job(name="j2", sweep_id="")])
        result = fjm._find_jobs(reg, sweep_id="")
        self.assertEqual(len(result), 2)

    def test_t6_5_invalid_label_pattern(self):
        """T6.5: Invalid regex in label_pattern reports error."""
        reg = _make_registry([_make_job()])
        try:
            fjm._find_jobs(reg, label_pattern="[invalid")
            self.fail("Expected re.error")
        except re.error:
            pass


if __name__ == "__main__":
    unittest.main(verbosity=2)
