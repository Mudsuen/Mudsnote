#!/usr/bin/env python3
"""Synthetic lifecycle bridge tests: no network, installed app or user state."""
import importlib.util
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('bridge', Path(__file__).with_name('macos_update_check.py'))
b = importlib.util.module_from_spec(spec)
spec.loader.exec_module(b)


class UpdateBridgeTests(unittest.TestCase):
    def test_missing_service_does_not_bootstrap_or_build(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(b, 'STATE', Path(tmp)):
            self.assertIsNone(b.load_runtime())

    def test_check_scopes_only_mudsnote_and_keeps_service_gates(self):
        runtime = Mock()
        runtime.check.return_value = {'Mudsnote': {'status': 'deferred', 'reason': 'app-in-use', 'error': 'private'}}
        result = b.check(runtime)
        self.assertEqual(result, {'status': 'deferred', 'reason': 'app-in-use'})
        runtime.check.assert_called_once_with(runtime.read.return_value, 'recipient', b.STATE, ['Mudsnote'], b.APP.parent)

    def test_only_running_app_deferral_schedules_install(self):
        for status in ('failed', 'unconfigured', 'backoff', 'unchanged'):
            self.assertFalse(b.waits_for_exit({'status': status}))
        self.assertFalse(b.waits_for_exit({'status': 'deferred', 'reason': 'rolled-back-release'}))
        self.assertTrue(b.waits_for_exit({'status': 'deferred', 'reason': 'app-in-use'}))

    def test_exit_watcher_waits_and_retries_if_app_reopens(self):
        runtime = Mock()
        from contextlib import nullcontext
        runtime.lock.return_value = nullcontext()
        runtime.running.side_effect = [True, False, True, False]
        with patch.object(b, 'check', side_effect=[{'status': 'deferred', 'reason': 'app-in-use'}, {'status': 'installed'}]) as check, patch.object(b.time, 'sleep') as sleep:
            b.install_after_exit(runtime)
        self.assertEqual(check.call_count, 2)
        self.assertEqual(sleep.call_count, 3)

    def test_watcher_does_not_retry_verification_failure_or_rollback(self):
        from contextlib import nullcontext
        for result in ({'status': 'failed'}, {'status': 'deferred', 'reason': 'rolled-back-release'}):
            runtime = Mock()
            runtime.lock.return_value = nullcontext()
            runtime.running.return_value = False
            with patch.object(b, 'check', return_value=result) as check, patch.object(b.time, 'sleep') as sleep:
                b.install_after_exit(runtime)
            check.assert_called_once()
            sleep.assert_not_called()

    def test_gui_process_honors_system_proxy_and_explicit_environment(self):
        with patch.dict(os.environ, {'HTTPS_PROXY': 'http://explicit:1234'}, clear=True), patch.object(b.urllib.request, 'getproxies', return_value={'http': 'http://127.0.0.1:6152', 'https': 'http://127.0.0.1:6152'}):
            b.configure_environment()
            self.assertEqual(os.environ['HTTP_PROXY'], 'http://127.0.0.1:6152')
            self.assertEqual(os.environ['HTTPS_PROXY'], 'http://explicit:1234')


if __name__ == '__main__':
    unittest.main()
