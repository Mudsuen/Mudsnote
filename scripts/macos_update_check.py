#!/usr/bin/env python3
"""App lifecycle bridge to the installed private, verified bundle updater."""
import argparse
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import urllib.request

STATE = Path.home() / 'Library/Application Support/DevflowUpdates'
APP = Path('/Applications/Mudsnote.app')


def configure_environment():
    os.environ['PATH'] = '/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin'
    os.environ['GIT_TERMINAL_PROMPT'] = '0'
    # GUI launches do not inherit a terminal's proxy. Honor macOS system proxies.
    for scheme, value in urllib.request.getproxies().items():
        if scheme in ('http', 'https'):
            os.environ.setdefault(scheme.upper() + '_PROXY', value)


def load_runtime():
    path = STATE / 'runtime/app_updates.py'
    if not path.is_file() or not path.with_name('apps.json').is_file():
        return None
    spec = importlib.util.spec_from_file_location('devflow_app_updates', path)
    runtime = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runtime)
    return runtime


def check(runtime):
    # Preserve the updater's serialization, backoff, signature, rollback and
    # app-in-use gates. Never build, quit, or open an application here.
    with contextlib.redirect_stdout(io.StringIO()):
        result = runtime.check(runtime.read(runtime.CONFIG), 'recipient', STATE,
                               ['Mudsnote'], APP.parent)['Mudsnote']
    return {key: result[key] for key in ('status', 'reason', 'revision') if key in result}


def waits_for_exit(result):
    return result.get('status') == 'deferred' and result.get('reason') in (
        'app-in-use', 'app-started-during-staging')


def install_after_exit(runtime):
    # A separate process survives normal quit and crashes. One watcher per Mac;
    # a reopened application still wins the updater's final running-app checks.
    with runtime.lock(STATE / 'mudsnote-exit-watch.lock'):
        deadline = time.monotonic() + 7 * 24 * 3600
        while time.monotonic() < deadline:
            if not runtime.running(APP):
                result = check(runtime)
                if not waits_for_exit(result):
                    return
            time.sleep(5)


def launch_exit_watcher():
    subprocess.Popen([sys.executable, str(Path(__file__).resolve()), '--after-exit'],
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--after-exit', action='store_true')
    args = parser.parse_args()
    configure_environment()
    runtime = load_runtime()
    if runtime is None:
        result = {'status': 'unconfigured'}
    elif args.after_exit:
        install_after_exit(runtime)
        return
    else:
        result = check(runtime)
        if waits_for_exit(result):
            launch_exit_watcher()
    print(json.dumps(result))


if __name__ == '__main__':
    try:
        main()
    except Exception:
        # Detailed service errors remain in its local failure receipt, never in
        # a menu or an alert that might expose account or transport information.
        print(json.dumps({'status': 'failed'}))
        sys.exit(1)
