#!/usr/bin/env python3
"""Synthetic update tests; no Keychain or real app access."""
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("updater", Path(__file__).with_name("macos_update.py"))
u = importlib.util.module_from_spec(spec)
spec.loader.exec_module(u)

class UpdateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        u.STATE = self.root / "state"
        u.APP = self.root / "Applications/Mudsnote.app"
        u.APP.mkdir(parents=True)
        (u.APP / "version").write_text("old")
        self.candidate = self.root / "candidate.app"
        self.candidate.mkdir()
        (self.candidate / "version").write_text("new")
        patch.object(u, "app_running", return_value=False).start()
        patch.object(u, "inspect_app", side_effect=lambda app: {"MudsnoteSourceRevision": (app / "version").read_text()}).start()
        patch.object(u, "command", side_effect=self.command).start()
        self.addCleanup(self.temp.cleanup)
        self.addCleanup(patch.stopall)

    def command(self, *args, **kwargs):
        if args[0] == "/usr/bin/ditto":
            shutil.copytree(args[1], args[2], dirs_exist_ok=True)
        else:
            raise AssertionError(f"Unexpected external command: {args}")

    def test_success_retains_previous_app_and_receipt(self):
        u.install_candidate(self.candidate)
        self.assertEqual((u.APP / "version").read_text(), "new")
        receipt = json.loads((u.STATE / "receipt.json").read_text())
        self.assertEqual((Path(receipt["backup"]) / "version").read_text(), "old")
        self.assertEqual(receipt["revision"], "new")
        self.assertFalse((u.STATE / "install-journal.json").exists())

    def test_running_app_is_not_replaced(self):
        with patch.object(u, "app_running", return_value=True):
            with self.assertRaises(RuntimeError): u.install_candidate(self.candidate)
        self.assertEqual((u.APP / "version").read_text(), "old")

    def test_app_started_during_staging_is_not_replaced(self):
        with patch.object(u, "app_running", side_effect=[False, True]):
            with self.assertRaises(RuntimeError): u.install_candidate(self.candidate)
        self.assertEqual((u.APP / "version").read_text(), "old")

    def test_invalid_candidate_preserves_old_app(self):
        with patch.object(u, "inspect_app", side_effect=RuntimeError("bad signature")):
            with self.assertRaises(RuntimeError): u.install_candidate(self.candidate)
        self.assertEqual((u.APP / "version").read_text(), "old")

    def test_failed_post_install_validation_restores_previous_app(self):
        def inspect(app):
            if app == u.APP and (app / "version").read_text() == "new": raise RuntimeError("verification failed")
            return {"MudsnoteSourceRevision": (app / "version").read_text()}
        with patch.object(u, "inspect_app", side_effect=inspect):
            with self.assertRaises(RuntimeError): u.install_candidate(self.candidate)
        self.assertEqual((u.APP / "version").read_text(), "old")

    def test_interrupted_swap_recovers_previous_app(self):
        u.STATE.mkdir()
        previous = u.APP.parent / ".Mudsnote-previous-test.app"
        u.APP.rename(previous)
        staged = u.APP.parent / ".Mudsnote-stage-test"
        staged.mkdir()
        u.atomic_json(u.STATE / "install-journal.json", {"previous": str(previous), "staged": str(staged)})
        u.recover_install()
        self.assertEqual((u.APP / "version").read_text(), "old")
        self.assertFalse(staged.exists())

    def test_installer_lock_excludes_concurrent_installation(self):
        with u.lock("install.lock"):
            with self.assertRaises(RuntimeError): u.install_candidate(self.candidate)
        self.assertEqual((u.APP / "version").read_text(), "old")

    def prepare_repo(self):
        repo = u.STATE / "source"
        repo.mkdir(parents=True)
        (u.STATE / "managed-source").touch()
        return repo

    def test_dirty_checkout_never_fetches_or_builds(self):
        self.prepare_repo()
        with patch.object(u, "git", side_effect=[u.REPOSITORY, " M Package.swift"]):
            with self.assertRaisesRegex(RuntimeError, "has edits"): u.run_update()

    def test_running_app_defers_before_network_or_build(self):
        with patch.object(u, "app_running", return_value=True): u.run_update()
        self.assertFalse((u.STATE / "source").exists())

    def test_failed_verification_never_builds_or_installs(self):
        repo = self.prepare_repo()
        calls = []
        def run(*args, **kwargs):
            calls.append(args)
            if args[0] == repo / "scripts/verify": raise subprocess.CalledProcessError(1, args)
        with patch.object(u, "git", side_effect=[u.REPOSITORY, "", "new"]), patch.object(u, "command", side_effect=run):
            with self.assertRaises(subprocess.CalledProcessError): u.run_update()
        self.assertFalse(any("package_app.sh" in str(call) for call in calls))
        self.assertEqual((u.APP / "version").read_text(), "old")

    def test_rewritten_history_never_checks_out_or_installs(self):
        self.prepare_repo()
        calls = []
        def run(*args, **kwargs):
            calls.append(args)
            if "merge-base" in args: raise subprocess.CalledProcessError(1, args)
        with patch.object(u, "git", side_effect=[u.REPOSITORY, "", "new"]), patch.object(u, "command", side_effect=run):
            with self.assertRaises(subprocess.CalledProcessError): u.run_update()
        self.assertFalse(any("checkout" in call for call in calls))
        self.assertEqual((u.APP / "version").read_text(), "old")

    def test_real_git_upgrade_then_noop_without_developer_checkout_changes(self):
        origin = self.root / "origin"
        origin.mkdir()
        def git(*args):
            return subprocess.check_output(["/usr/bin/git", "-C", str(origin), *args], text=True).strip()
        git("init", "-b", "main")
        git("config", "user.email", "fixture@example.invalid")
        git("config", "user.name", "Fixture")
        (origin / ".gitignore").write_text("dist/\n")
        git("add", ".gitignore"); git("commit", "-m", "old")
        old = git("rev-parse", "HEAD")
        (u.APP / "version").write_text(old)
        (origin / "change").write_text("new source")
        git("add", "change"); git("commit", "-m", "new")
        new = git("rev-parse", "HEAD")
        (origin / "local-work").write_text("must survive")
        builds = []
        def run(*args, cwd=None, capture=False):
            if args[0] == "/usr/bin/git":
                return subprocess.run([str(a) for a in args], cwd=cwd, check=True, text=True,
                    stdout=subprocess.PIPE if capture else subprocess.DEVNULL).stdout
            if str(args[0]).endswith("scripts/verify"):
                builds.append("verify")
            elif str(args[0]).endswith("scripts/package_app.sh"):
                builds.append("build")
                target = u.STATE / "source/dist/Mudsnote.app"
                target.mkdir(parents=True)
                (target / "version").write_text(new)
            else:
                return self.command(*args)
        with patch.object(u, "REPOSITORY", str(origin)), patch.object(u, "command", side_effect=run):
            u.run_update()
            u.run_update()
        self.assertEqual((u.APP / "version").read_text(), new)
        self.assertEqual(builds, ["verify", "build"])
        self.assertEqual((origin / "local-work").read_text(), "must survive")
        self.assertEqual(git("branch", "--show-current"), "main")

if __name__ == "__main__": unittest.main()
