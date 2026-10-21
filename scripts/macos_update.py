#!/usr/bin/env python3
"""Personal Mac updates from a dedicated Git checkout; never touches a developer checkout."""
import argparse
import contextlib
import datetime
import fcntl
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import time
import uuid

REPOSITORY = "https://github.com/Mudsuen/Mudsnote.git"
LABEL = "local.codex.mudsnote.update"
STATE = Path.home() / "Library/Application Support/Mudsnote/Updates"
APP = Path("/Applications/Mudsnote.app")
AGENT = Path.home() / "Library/LaunchAgents" / (LABEL + ".plist")


def command(*args, cwd=None, capture=False):
    return subprocess.run([str(a) for a in args], cwd=cwd, check=True,
                          text=True, stdout=subprocess.PIPE if capture else None).stdout


def atomic_json(path, value):
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n")
    temporary.replace(path)


@contextlib.contextmanager
def lock(name):
    STATE.mkdir(parents=True, exist_ok=True)
    with (STATE / name).open("a") as handle:
        try:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError("Another update or installation is already running.")
        yield


def app_running():
    # Match the installed executable, including an invocation with QA arguments.
    result = subprocess.run(["/usr/bin/pgrep", "-f", "^" + str(APP / "Contents/MacOS/Mudsnote") + "( |$)"],
                            stdout=subprocess.DEVNULL)
    if result.returncode not in (0, 1):
        raise RuntimeError("Unable to establish whether Mudsnote is running.")
    return result.returncode == 0


def inspect_app(app):
    with (app / "Contents/Info.plist").open("rb") as handle:
        info = plistlib.load(handle)
    if info.get("CFBundleIdentifier") != "local.codex.mudsnote" or info.get("CFBundleExecutable") != "Mudsnote":
        raise RuntimeError("Unexpected application identity.")
    if not (app / "Contents/MacOS/Mudsnote").is_file():
        raise RuntimeError("Candidate executable is missing.")
    command("/usr/bin/codesign", "--verify", "--deep", "--strict", app)
    return info


def quit_app():
    if app_running():
        command("/usr/bin/osascript", "-e", 'tell application id "local.codex.mudsnote" to quit')
        for _ in range(40):
            if not app_running():
                return
            time.sleep(0.25)
        raise RuntimeError("Mudsnote has not exited; save or dismiss its dialog and try again. No forced quit was used.")


def recover_install():
    journal = STATE / "install-journal.json"
    if not journal.exists():
        return
    record = json.loads(journal.read_text())
    previous = Path(record["previous"])
    staged = Path(record["staged"])
    # Recover only paths owned by this installer in the application directory.
    if previous.parent != APP.parent or staged.parent != APP.parent or not previous.name.startswith(".Mudsnote-previous-") or not staged.name.startswith(".Mudsnote-stage-"):
        raise RuntimeError("Invalid installation recovery journal.")
    if not APP.exists() and previous.exists():
        previous.rename(APP)
    elif previous.exists():
        inspect_app(APP)
        backup = STATE / "backups" / previous.name
        backup.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(previous), str(backup))
        atomic_json(STATE / "receipt.json", {"revision": inspect_app(APP).get("MudsnoteSourceRevision"),
                                          "backup": str(backup), "installed_at": datetime.datetime.now().isoformat()})
    if staged.exists():
        shutil.rmtree(staged)
    journal.unlink()


def install_candidate(candidate, *, allow_quit=False, launch=False):
    info = inspect_app(candidate)
    with lock("install.lock"):
        recover_install()
        if allow_quit:
            quit_app()
        if app_running():
            raise RuntimeError("Mudsnote is running; installation deferred until it exits.")
        staged = Path(tempfile.mkdtemp(prefix=".Mudsnote-stage-", dir=APP.parent))
        previous = APP.parent / (".Mudsnote-previous-" + uuid.uuid4().hex + ".app")
        try:
            # ditto preserves resource forks and signature metadata.
            command("/usr/bin/ditto", candidate, staged)
            inspect_app(staged)
            if app_running():
                raise RuntimeError("Mudsnote started while preparing the update; installation deferred.")
            atomic_json(STATE / "install-journal.json", {"previous": str(previous), "staged": str(staged)})
            if APP.exists():
                APP.rename(previous)
            try:
                staged.rename(APP)
                inspect_app(APP)
            except BaseException:
                if APP.exists():
                    shutil.rmtree(APP)
                if previous.exists():
                    previous.rename(APP)
                (STATE / "install-journal.json").unlink(missing_ok=True)
                raise
            if previous.exists():
                recover_install()
            else:
                (STATE / "install-journal.json").unlink()
                atomic_json(STATE / "receipt.json", {"revision": info.get("MudsnoteSourceRevision"),
                    "backup": None, "installed_at": datetime.datetime.now().isoformat()})
        finally:
            if staged.exists():
                shutil.rmtree(staged)
        print("Installed revision:", info.get("MudsnoteSourceRevision", "unknown"))
    if launch:
        command("/usr/bin/open", APP)


def git(repo, *args):
    return command("/usr/bin/git", "-C", repo, *args, capture=True).strip()


def run_update():
    os.environ["GIT_TERMINAL_PROMPT"] = "0"
    with lock("update.lock"):
        with lock("install.lock"):
            recover_install()
        if app_running():
            print("Deferred: Mudsnote is in use. The next check will retry after it exits.")
            return
        repo = STATE / "source"
        marker = STATE / "managed-source"
        if not repo.exists():
            clone = STATE / ("clone-" + uuid.uuid4().hex)
            try:
                command("/usr/bin/git", "clone", "--branch", "main", REPOSITORY, clone)
                clone.rename(repo)
                marker.touch()
            finally:
                if clone.exists():
                    shutil.rmtree(clone)
        if not marker.exists() or git(repo, "remote", "get-url", "origin") != REPOSITORY:
            raise RuntimeError("Refusing to update an unmanaged source checkout.")
        if git(repo, "status", "--porcelain"):
            raise RuntimeError("Managed source checkout has edits; leaving it untouched.")
        command("/usr/bin/git", "-C", repo, "fetch", "origin", "main")
        revision = git(repo, "rev-parse", "origin/main")
        installed = inspect_app(APP).get("MudsnoteSourceRevision") if APP.exists() else None
        if installed == revision:
            print("Already current:", revision)
            return
        if installed:
            # Never downgrade or follow a rewritten branch automatically.
            command("/usr/bin/git", "-C", repo, "merge-base", "--is-ancestor", installed, revision)
        command("/usr/bin/git", "-C", repo, "checkout", "--detach", revision)
        candidate = repo / "dist/Mudsnote.app"
        verified = STATE / "verified-revision"
        if not verified.exists() or verified.read_text().strip() != revision or not candidate.exists():
            command(repo / "scripts/verify", "macos", "pr", cwd=repo)
            command(repo / "scripts/package_app.sh", "--candidate-only", cwd=repo)
            verified.write_text(revision + "\n")
        if inspect_app(candidate).get("MudsnoteSourceRevision") != revision:
            verified.unlink(missing_ok=True)
            raise RuntimeError("Built revision does not match the fetched commit.")
        if app_running():
            print("Candidate ready; installation deferred until Mudsnote exits.")
            return
        install_candidate(candidate)
        bootstrap = STATE / "macos_update.py"
        if bootstrap.exists():
            replacement = STATE / "macos_update.py.next"
            shutil.copy2(repo / "scripts/macos_update.py", replacement)
            replacement.replace(bootstrap)


def install_agent():
    STATE.mkdir(parents=True, exist_ok=True)
    command("/usr/bin/xcrun", "--find", "swift")
    # Stable bootstrap: future Git checkouts cannot invalidate launchd's program path.
    bootstrap = STATE / "macos_update.py"
    if Path(__file__).resolve() != bootstrap.resolve():
        shutil.copy2(__file__, bootstrap)
    AGENT.parent.mkdir(parents=True, exist_ok=True)
    configuration = {"Label": LABEL, "ProgramArguments": [sys.executable, str(bootstrap), "run"],
        "StartInterval": 900, "RunAtLoad": True, "ProcessType": "Background",
        "EnvironmentVariables": {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin"},
        "StandardOutPath": str(STATE / "agent.log"), "StandardErrorPath": str(STATE / "agent.log")}
    subprocess.run(["/bin/launchctl", "bootout", f"gui/{os.getuid()}/{LABEL}"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    with AGENT.open("wb") as handle:
        plistlib.dump(configuration, handle)
    command("/bin/launchctl", "bootstrap", f"gui/{os.getuid()}", AGENT)
    print("Automatic update checks enabled every 15 minutes. State:", STATE)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    for action in ("run", "status", "install-agent", "uninstall-agent", "rollback"):
        sub.add_parser(action)
    install = sub.add_parser("install-candidate")
    install.add_argument("candidate", type=Path)
    install.add_argument("--quit", action="store_true")
    install.add_argument("--launch", action="store_true")
    args = parser.parse_args()
    if args.action == "run":
        run_update()
    elif args.action == "install-agent":
        install_agent()
    elif args.action == "uninstall-agent":
        subprocess.run(["/bin/launchctl", "bootout", f"gui/{os.getuid()}/{LABEL}"], check=False)
        AGENT.unlink(missing_ok=True)
        print("Automatic updates disabled; installed app and recovery backups retained.")
    elif args.action == "status":
        print("Agent configured:", AGENT.exists())
        print("Installed revision:", inspect_app(APP).get("MudsnoteSourceRevision", "unrecorded") if APP.exists() else "not installed")
        receipt = STATE / "receipt.json"
        print(receipt.read_text() if receipt.exists() else "No installation receipt yet.")
    elif args.action == "rollback":
        if AGENT.exists():
            raise RuntimeError("Disable automatic updates with uninstall-agent before rollback.")
        receipt = json.loads((STATE / "receipt.json").read_text())
        if not receipt.get("backup"):
            raise RuntimeError("No previous app is available.")
        backup = Path(receipt["backup"])
        if backup.parent != STATE / "backups":
            raise RuntimeError("Invalid backup path.")
        install_candidate(backup)
    else:
        install_candidate(args.candidate.resolve(), allow_quit=args.quit, launch=args.launch)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, ValueError, subprocess.CalledProcessError) as error:
        print("Update stopped:", error, file=sys.stderr)
        sys.exit(1)
