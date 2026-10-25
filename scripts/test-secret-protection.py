#!/usr/bin/env python3
"""Exercise protection in disposable repositories. Test credentials are synthesized, never real."""
import importlib.util
import os
import sys
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
CHECKER = ROOT / "scripts/check-secrets.py"
spec = importlib.util.spec_from_file_location("secret_policy", CHECKER)
policy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(policy)

class SecretProtectionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="recorder-secret-test-")
        self.repo = Path(self.temp.name)
        (self.repo / "scripts").mkdir()
        (self.repo / "scripts/check-secrets.py").write_bytes(CHECKER.read_bytes())
        binary = self.repo / ".build/security-tools/gitleaks"
        binary.parent.mkdir(parents=True)
        binary.symlink_to(ROOT / ".build/security-tools/gitleaks")
        self.git("init", "--quiet")
        self.git("config", "user.name", "Synthetic Test")
        self.git("config", "user.email", "test@example.invalid")
        # No global hooks/configuration or real credential helpers are used.
        self.git("config", "core.hooksPath", str(ROOT / ".githooks"))
    def tearDown(self):
        self.temp.cleanup()
    def git(self, *args, check=True):
        env = os.environ.copy()
        env["GIT_CONFIG_NOSYSTEM"] = "1"
        env["GIT_CONFIG_GLOBAL"] = os.devnull
        return subprocess.run(["git", *args], cwd=self.repo, env=env, check=check, capture_output=True)
    def staged(self, name, text):
        path = self.repo / name; path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        self.git("add", "-f", "--", name)
    def check(self, mode="staged", input=None, extra=()):
        return subprocess.run([sys.executable, str(self.repo / "scripts/check-secrets.py"), mode, *extra], cwd=self.repo, input=input, capture_output=True)
    def test_filename_rules_cover_nested_env_keys_and_runtime(self):
        for name in [".env", ".env.local", "nested/.env.production", "app.env", "nested/app.env.staging", ".env.example", ".ENV", ".envrc", "id_rsa", "identity.p12", "key.pem", "credentials.json", "secrets.json", "TaskInbox/inbox.json", "processing-queue.json", "profiles.json.corrupt-1", "meeting.json", "export.csv", "audio.wav"]:
            with self.subTest(name=name): self.assertTrue(policy.prohibited(name))
        for name in ["Sources/Recorder/APIKeyEntryField.swift", "Package.resolved", "Sources/Recorder/Resources/models.json", ".github/workflows/secret-protection.yml", "scripts/check-secrets.py"]:
            with self.subTest(name=name): self.assertFalse(policy.prohibited(name))
    def test_ignore_file_blocks_force_add_candidates_normally(self):
        (self.repo / ".gitignore").write_bytes((ROOT / ".gitignore").read_bytes())
        for name in [".env", ".ENV", "nested/.env.local", "app.env", "foo.env.production", "secrets.json", "key.pem", "TaskInbox/inbox.json", "processing-queue.json"]:
            self.assertEqual(self.git("check-ignore", "--quiet", "--", name, check=False).returncode, 0, name)
    def test_force_added_env_blocks_real_commit(self):
        self.staged("nested/.env", "SYNTHETIC_VALUE=placeholder\n")
        result = self.git("commit", "-m", "synthetic", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"BLOCKED", result.stderr)
    def test_secret_in_ordinary_source_blocks_and_is_not_printed(self):
        import hashlib
        fake = "gh" + "p_" + hashlib.sha256(b"synthetic-github-fixture").hexdigest()[:36]
        self.staged("ordinary.txt", fake)
        result = self.check()
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(fake.encode() not in result.stdout + result.stderr, "Scanner output must redact values")
    def test_providerless_todoist_style_key_is_blocked(self):
        import hashlib
        fake = hashlib.sha1(b"synthetic-secret-scanner-fixture").hexdigest()
        self.staged("ordinary.conf", "TODOIST_API_KEY=" + fake + "\n")
        result = self.check()
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(fake.encode() not in result.stdout + result.stderr, "Scanner output must redact values")
    def test_safe_source_can_commit(self):
        self.staged("ordinary.txt", "Harmless synthetic documentation\n")
        result = self.git("commit", "-m", "safe", check=False)
        self.assertEqual(result.returncode, 0, result.stderr.decode())
    def test_deleted_secret_path_is_still_blocked_by_history_check(self):
        self.staged(".env", "SYNTHETIC_VALUE=placeholder\n")
        # Deliberately bypass the hook ONLY in this disposable repository to exercise history scanning.
        self.git("-c", "core.hooksPath=/dev/null", "commit", "-m", "synthetic forbidden history")
        self.git("rm", ".env")
        self.git("-c", "core.hooksPath=/dev/null", "commit", "-m", "remove synthetic fixture")
        self.assertNotEqual(self.check("history").returncode, 0)
    def test_pre_push_inspects_explicit_unreferenced_tip(self):
        self.staged("safe.txt", "safe\n"); self.git("commit", "-m", "safe")
        first = self.git("rev-parse", "HEAD").stdout.decode().strip()
        self.staged(".env.local", "SYNTHETIC_VALUE=placeholder\n")
        self.git("-c", "core.hooksPath=/dev/null", "commit", "-m", "synthetic unreferenced tip")
        forbidden = self.git("rev-parse", "HEAD").stdout.decode().strip()
        self.git("checkout", "--detach", first)
        self.git("branch", "-D", "master", check=False)
        self.git("branch", "-D", "main", check=False)
        data = f"HEAD {forbidden} refs/heads/test {'0'*40}\n".encode()
        result = self.check("history", data, ("--pre-push",))
        self.assertNotEqual(result.returncode, 0)
    def test_missing_scanner_blocks_instead_of_skipping(self):
        binary = self.repo / ".build/security-tools/gitleaks"
        binary.unlink()
        tools = self.repo / "test-tools"; tools.mkdir()
        import shutil
        (tools / "git").symlink_to(shutil.which("git"))
        env = os.environ.copy(); env["PATH"] = str(tools)
        result = subprocess.run([sys.executable, str(self.repo / "scripts/check-secrets.py"), "staged"], cwd=self.repo, env=env, capture_output=True)
        self.assertEqual(result.returncode, 2); self.assertIn(b"Gitleaks missing", result.stderr)
    def test_scanner_internal_error_fails_closed_even_with_zero_exit(self):
        binary = self.repo / ".build/security-tools/gitleaks"; binary.unlink()
        binary.write_text("#!/bin/sh\nprintf 'ERR synthetic scanner failure\n' >&2\nexit 0\n")
        binary.chmod(0o700)
        result = self.check()
        self.assertNotEqual(result.returncode, 0)
    def test_installed_hooks_survive_missing_worktree_scripts(self):
        import shutil
        managed = self.repo / ".git/recorder-security"
        (managed / "hooks").mkdir(parents=True)
        (managed / "scripts").mkdir()
        (managed / ".build/security-tools").mkdir(parents=True)
        shutil.copy2(CHECKER, managed / "scripts/check-secrets.py")
        shutil.copy2(ROOT / ".githooks/pre-commit", managed / "hooks/pre-commit")
        (managed / ".build/security-tools/gitleaks").symlink_to(ROOT / ".build/security-tools/gitleaks")
        self.git("config", "core.hooksPath", str(managed / "hooks"))
        shutil.rmtree(self.repo / "scripts"); shutil.rmtree(self.repo / ".build")
        self.staged("safe.txt", "safe\n")
        self.assertEqual(self.git("commit", "-m", "safe", check=False).returncode, 0)
        self.staged(".env", "SYNTHETIC_VALUE=placeholder\n")
        self.assertNotEqual(self.git("commit", "-m", "blocked", check=False).returncode, 0)
    def test_real_push_hook_blocks_forbidden_history_before_local_upload(self):
        remote = self.repo / "disposable-remote.git"
        self.git("init", "--bare", "--quiet", str(remote))
        self.staged(".env", "SYNTHETIC_VALUE=placeholder\n")
        self.git("-c", "core.hooksPath=/dev/null", "commit", "-m", "synthetic forbidden history")
        result = self.git("push", str(remote), "HEAD:refs/heads/test", check=False)
        self.assertNotEqual(result.returncode, 0)
        refs = self.git("--git-dir", str(remote), "show-ref", check=False)
        self.assertNotEqual(refs.returncode, 0)
    def test_ref_deletion_is_allowed_without_upload(self):
        data = f"(delete) {'0'*40} refs/heads/test {'1'*40}\n".encode()
        self.assertEqual(self.check("history", data, ("--pre-push",)).returncode, 0)

if __name__ == "__main__":
    unittest.main()
