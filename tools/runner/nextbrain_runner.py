#!/usr/bin/env python3
"""
NextBrain build runner (D-146, tools/runner/README.md) — builds app versions on a computer you already have, for free.

It asks our server for the versions the super admin created in Dashboard › App versions with "Build on: my computer",
then runs the SAME workflow of codemagic.yaml that Codemagic would run — read from the commit being built — on this
machine: Windows builds Windows, Android and web; Linux (or WSL) builds Linux, Android and web. The workflow's own
last step uploads the files to our server (scripts/release/upload_artifacts.sh with the per-release upload token), so
a version built here is published, offered for download and rolled back exactly like one built on Codemagic.

    POST {NB_API_URL}/api/v1/builder/runner/claim               → a job {id, attempt, workflow, branch, variables}
    POST {NB_API_URL}/api/v1/builder/runner/jobs/{id}/report    log lines, status, progress (also the heartbeat)
    POST {NB_API_URL}/api/v1/builder/runner/jobs/{id}/finish    ok / error

A 409 on a job call means the super admin canceled it (or it was retried): the running step is killed.

Configuration — environment variables, or KEY=VALUE lines in tools/runner/runner.env (never committed):
    NB_BUILDER_TOKEN     the token from App versions › Build runner › New token (shown once)        [required]
    NB_API_URL           default https://nextbrain.site/api
    NB_REPO_URL          the app repository to clone (default: this checkout's `origin`)
    NB_RUNNER_NAME       how the dashboard names this machine (default: the computer name)
    NB_RUNNER_PLATFORMS  what it builds (default windows,android,web on Windows; linux,android,web on Linux)
    NB_WORK_DIR          its own clone and the kept symbols (default ~/nextbrain-runner)
    NB_KEY_PROPERTIES    the Android release key.properties (storeFile, storePassword, keyAlias, keyPassword)
    NB_BASH              Git Bash on Windows (default: found under Program Files\\Git)
    NB_POLL_SECONDS      default 15

    py tools/runner/nextbrain_runner.py --check    # checks the setup and the token, builds nothing
    py tools/runner/nextbrain_runner.py            # waits for versions to build (Ctrl+C stops it)

Needs Python 3.9+ and PyYAML (`py -m pip install pyyaml`). Secrets (the token, the upload token, the key passwords)
are masked in every line sent to the server.
"""
from __future__ import annotations

import argparse
import json
import os
import platform as pf
import re
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Dict, List, Optional

VERSION = "1.0.0"
HERE = Path(__file__).resolve().parent
IS_WIN = os.name == "nt"
BRANCH_RE = re.compile(r"^[A-Za-z0-9._/-]{1,100}$")
WORKFLOW_RE = re.compile(r"^[A-Za-z0-9._-]{1,100}$")
DEFAULT_PLATFORMS = {"windows": "windows,android,web", "linux": "linux,android,web", "macos": "android,web"}


class StepFailed(Exception):
    pass


class JobGone(Exception):
    pass


# ── configuration ─────────────────────────────────────────────────────────────

def os_name() -> str:
    return "windows" if IS_WIN else ("macos" if sys.platform == "darwin" else "linux")


def load_env_file(path: Path) -> Dict[str, str]:
    out: Dict[str, str] = {}
    if path.is_file():
        for line in path.read_text(encoding="utf-8-sig").splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                out[k.strip()] = v.strip().strip('"').strip("'")
    return out


def read_properties(path: Path) -> Dict[str, str]:
    return load_env_file(path)


class Config:
    def __init__(self, env: Dict[str, str]):
        def get(k: str, default: str = "") -> str:
            return (env.get(k) or os.environ.get(k) or default).strip()

        self.token = get("NB_BUILDER_TOKEN")
        self.api_url = get("NB_API_URL", "https://nextbrain.site/api").rstrip("/")
        self.repo_url = get("NB_REPO_URL") or self._origin()
        self.name = get("NB_RUNNER_NAME", socket.gethostname())[:60]
        self.platforms = [p.strip().lower() for p in get("NB_RUNNER_PLATFORMS", DEFAULT_PLATFORMS[os_name()]).split(",")
                          if p.strip()]
        self.work_dir = Path(get("NB_WORK_DIR", str(Path.home() / "nextbrain-runner"))).expanduser()
        kp = get("NB_KEY_PROPERTIES")
        self.key_properties = Path(kp).expanduser() if kp else None
        self.bash = get("NB_BASH") or self._find_bash()
        self.poll = float(get("NB_POLL_SECONDS", "15") or 15)

    @staticmethod
    def _origin() -> str:
        try:
            return subprocess.run(["git", "-C", str(HERE), "remote", "get-url", "origin"], capture_output=True,
                                  text=True, timeout=30).stdout.strip()
        except (OSError, subprocess.SubprocessError):
            return ""

    @staticmethod
    def _find_bash() -> str:
        if not IS_WIN:
            return shutil.which("bash") or "/bin/bash"
        for base in (os.environ.get("ProgramFiles", r"C:\Program Files"), os.environ.get("ProgramW6432", ""),
                     os.environ.get("LOCALAPPDATA", "") + r"\Programs"):
            p = Path(base) / "Git" / "bin" / "bash.exe"
            if base and p.is_file():
                return str(p)
        return ""

    def secrets(self) -> List[str]:
        out = [self.token]
        m = re.match(r"^[a-z+]+://([^@/]+)@", self.repo_url)
        if m:
            out.append(m.group(1))
        if self.key_properties and self.key_properties.is_file():
            props = read_properties(self.key_properties)
            out += [props.get("storePassword", ""), props.get("keyPassword", "")]
        return [s for s in out if s and len(s) >= 4]


# ── the server ────────────────────────────────────────────────────────────────

class Api:
    def __init__(self, cfg: Config):
        self.cfg = cfg
        self.base = f"{cfg.api_url}/api/v1/builder/runner"

    def post(self, path: str, body: dict, timeout: float = 60) -> Optional[dict]:
        req = urllib.request.Request(f"{self.base}{path}", data=json.dumps(body).encode(), method="POST", headers={
            "Authorization": f"Builder {self.cfg.token}", "Content-Type": "application/json",
            "User-Agent": f"nextbrain-runner/{VERSION}"})
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:   # noqa: S310  our own https API
                raw = r.read()
                return json.loads(raw) if r.status != 204 and raw else None
        except urllib.error.HTTPError as e:
            if e.code == 409:
                raise JobGone(path)
            text = e.read()[:400].decode("utf-8", "replace")
            raise RuntimeError(f"HTTP {e.code} on {path}: {text}")

    def claim(self) -> Optional[dict]:
        return self.post("/claim", {"name": self.cfg.name, "os": os_name(), "platforms": self.cfg.platforms,
                                    "version": VERSION})


class LogPump:
    """Sends the buffered lines every 2 s (and an empty report every 20 s as the heartbeat). A 409 → canceled."""

    def __init__(self, api: Api, job: dict, secrets: List[str], on_cancel):
        self.api, self.job, self.on_cancel = api, job, on_cancel
        self.secrets = sorted({s for s in secrets if s}, key=len, reverse=True)
        self.lines: List[str] = []
        self.fields: Dict[str, object] = {}
        self.lock, self.send_lock = threading.Lock(), threading.Lock()
        self.canceled, self.stop = threading.Event(), threading.Event()
        self.last = 0.0
        self.t = threading.Thread(target=self._loop, daemon=True)

    def mask(self, s: str) -> str:
        for x in self.secrets:
            s = s.replace(x, "****")
        return s

    def write(self, line: str) -> None:
        line = self.mask(line.rstrip("\r\n"))[:2000]
        print(line, flush=True)
        with self.lock:
            self.lines.append(line)

    def set(self, **fields) -> None:
        with self.lock:
            self.fields.update(fields)
        self.flush()

    def flush(self) -> None:
        with self.send_lock:
            with self.lock:
                lines, fields = self.lines[:500], dict(self.fields)
                self.lines, self.fields = self.lines[500:], {}
            if not lines and not fields and time.monotonic() - self.last < 20:
                return
            try:
                self.api.post(f"/jobs/{self.job['id']}/report", {"attempt": self.job["attempt"], "lines": lines,
                                                                  **fields}, timeout=30)
                self.last = time.monotonic()
            except JobGone:
                if not self.canceled.is_set():
                    self.canceled.set()
                    self.on_cancel()
            except Exception as exc:  # noqa: BLE001  a network blip: keep the lines for the next try
                with self.lock:
                    self.lines[:0] = lines
                    for k, v in fields.items():
                        self.fields.setdefault(k, v)
                print(f"(report failed: {exc.__class__.__name__}; retrying)", file=sys.stderr, flush=True)

    def _loop(self) -> None:
        while not self.stop.wait(2):
            self.flush()

    def __enter__(self):
        self.t.start()
        return self

    def __exit__(self, *exc):
        self.stop.set()
        self.t.join(timeout=10)
        if not self.canceled.is_set():
            self.flush()


# ── one build ─────────────────────────────────────────────────────────────────

class Build:
    def __init__(self, cfg: Config, api: Api, job: dict):
        self.cfg, self.api, self.job = cfg, api, job
        self.src = cfg.work_dir / "src"
        self.proc: Optional[subprocess.Popen] = None
        self.pump: Optional[LogPump] = None
        self.deadline = 0.0

    def say(self, msg: str) -> None:
        if self.pump:
            self.pump.write(f"==> {msg}")

    def kill(self) -> None:
        p = self.proc
        if p is None or p.poll() is not None:
            return
        try:
            if IS_WIN:
                subprocess.run(["taskkill", "/PID", str(p.pid), "/T", "/F"], capture_output=True, timeout=60)
            else:
                os.killpg(p.pid, signal.SIGTERM)
                try:
                    p.wait(10)
                except subprocess.TimeoutExpired:
                    os.killpg(p.pid, signal.SIGKILL)
        except (OSError, subprocess.SubprocessError):
            pass

    def run(self, cmd: List[str], what: str, env: Optional[dict] = None, cwd: Optional[Path] = None,
            capture: Optional[List[str]] = None) -> None:
        if self.pump and self.pump.canceled.is_set():
            raise JobGone(what)
        left = max(1.0, self.deadline - time.monotonic())
        kw = {"start_new_session": True} if not IS_WIN else \
            {"creationflags": getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)}
        self.proc = subprocess.Popen(cmd, cwd=str(cwd or self.src), env=env or os.environ.copy(),  # noqa: S603
                                     stdout=subprocess.PIPE, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
                                     text=True, encoding="utf-8", errors="replace", **kw)
        timer = threading.Timer(left, self.kill)
        timer.daemon = True
        timer.start()
        start = time.monotonic()
        try:
            assert self.proc.stdout is not None
            for line in self.proc.stdout:
                if self.pump:
                    self.pump.write(line)
                if capture is not None:
                    capture.append(line.strip())
            code = self.proc.wait()
        finally:
            timer.cancel()
            self.proc = None
        if self.pump and self.pump.canceled.is_set():
            raise JobGone(what)
        if code != 0:
            if time.monotonic() - start >= left - 1:
                raise StepFailed(f"timeout in {what} (max_build_duration)")
            raise StepFailed(f"{what}: exit {code}")

    def checkout(self, branch: str) -> str:
        if not BRANCH_RE.match(branch) or ".." in branch or branch.startswith(("-", "/")):
            raise StepFailed(f"branch_invalid: {branch}")
        self.cfg.work_dir.mkdir(parents=True, exist_ok=True)
        if not (self.src / ".git").exists():
            self.say("git clone")
            shutil.rmtree(self.src, ignore_errors=True)
            self.run(["git", "clone", "--quiet", "--no-checkout", self.cfg.repo_url, str(self.src)], "clone",
                     cwd=self.cfg.work_dir)
        self.say(f"git fetch origin/{branch}")
        self.run(["git", "fetch", "--quiet", "--prune", "origin", f"+refs/heads/{branch}:refs/remotes/origin/{branch}"],
                 "fetch")
        out: List[str] = []
        self.run(["git", "rev-parse", f"refs/remotes/origin/{branch}^{{commit}}"], "rev-parse", capture=out)
        sha = out[-1] if out else ""
        if not re.match(r"^[0-9a-f]{40,64}$", sha):
            raise StepFailed(f"branch_not_found: {branch}")
        self.run(["git", "checkout", "--quiet", "--force", "--detach", sha], "checkout")
        self.run(["git", "clean", "-ffdxq"], "clean")
        self.say(f"commit {sha}")
        return sha

    def workflow(self, workflow_id: str) -> dict:
        try:
            import yaml
        except ImportError:
            raise StepFailed("pyyaml_missing: run `py -m pip install pyyaml` on the runner")
        doc = yaml.safe_load((self.src / "codemagic.yaml").read_text(encoding="utf-8"))
        wf = (doc.get("workflows") or {}).get(workflow_id)
        if not isinstance(wf, dict):
            raise StepFailed(f"workflow_not_found: {workflow_id} is not in codemagic.yaml at this commit")
        flutter = ((doc.get("definitions") or {}).get("flutter_version"))
        if flutter:
            out: List[str] = []
            try:
                self.run(self._flutter_cmd() + ["--version"], "flutter --version", capture=out)
                if not any(str(flutter) in ln for ln in out):
                    self.say(f"note: codemagic.yaml pins Flutter {flutter}; this machine has "
                             f"{(out[0] if out else '?')[:80]}")
            except StepFailed:
                raise StepFailed("flutter_missing: `flutter` is not on this machine's PATH")
        return wf

    @staticmethod
    def _flutter_cmd() -> List[str]:
        return [shutil.which("flutter.bat") or "flutter.bat"] if IS_WIN else ["flutter"]

    def signing_env(self) -> Dict[str, str]:
        kp = self.cfg.key_properties
        if kp is None or not kp.is_file():
            raise StepFailed("signing_key_missing: set NB_KEY_PROPERTIES to the Android release key.properties")
        p = read_properties(kp)
        try:
            store = Path(p["storeFile"]).expanduser()
            if not store.is_absolute():
                store = (kp.parent / store).resolve()
            if not store.is_file():
                raise StepFailed(f"signing_key_missing: the keystore {store} does not exist")
            return {"ANDROID_KEYSTORE_PATH": str(store), "ANDROID_KEYSTORE_PASSWORD": p["storePassword"],
                    "ANDROID_KEY_ALIAS": p["keyAlias"], "ANDROID_KEY_PASSWORD": p["keyPassword"]}
        except KeyError as exc:
            raise StepFailed(f"signing_key_missing: key.properties lacks {exc.args[0]}")

    def shims(self) -> Path:
        """Git Bash has no `zip`: a tiny one (python's zipfile) for the workflows' `zip -qr <dest> <paths>`."""
        d = self.cfg.work_dir / "bin"
        d.mkdir(parents=True, exist_ok=True)
        py = Path(sys.executable).as_posix()
        (d / "zip").write_text(f'#!/usr/bin/env bash\nexec "{py}" "{(HERE / "zip_shim.py").as_posix()}" "$@"\n',
                               encoding="utf-8", newline="\n")
        return d

    def base_env(self, wf: dict, sha: str, cm_env: Path) -> Dict[str, str]:
        env = os.environ.copy()
        envd = wf.get("environment") or {}
        for k, v in (envd.get("vars") or {}).items():
            env[str(k)] = str(v)
        for k, v in (self.job.get("variables") or {}).items():
            env[str(k)] = str(v)
        if envd.get("android_signing"):
            env.update(self.signing_env())
        src = self.src.as_posix() if IS_WIN else str(self.src)
        env.update({"CI": "true", "CM_BUILD_DIR": src, "CM_BRANCH": self.job["branch"], "CM_COMMIT": sha,
                    "CM_ENV": cm_env.as_posix() if IS_WIN else str(cm_env), "NB_RUNNER": self.cfg.name})
        if IS_WIN and not shutil.which("zip"):
            env["PATH"] = str(self.shims()) + os.pathsep + env.get("PATH", "")
        return env

    @staticmethod
    def read_cm_env(path: Path, env: Dict[str, str]) -> None:
        if path.is_file():
            for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
                if "=" in line and not line.startswith("#"):
                    k, v = line.split("=", 1)
                    env[k.strip()] = v

    def step_cmd(self, wf: dict, script: str, tmp: Path, i: int) -> List[str]:
        windows_wf = str(wf.get("instance_type") or "").startswith("windows")
        first = script.lstrip().splitlines()[0] if script.strip() else ""
        if windows_wf and not first.startswith("#!"):
            f = tmp / f"step{i}.ps1"
            f.write_text(script, encoding="utf-8-sig")
            return ["powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", str(f)]
        if first.startswith("#!") and "python" in first:
            f = tmp / f"step{i}.py"
            f.write_text(script, encoding="utf-8")
            return [sys.executable, str(f)]
        if not self.cfg.bash:
            raise StepFailed("bash_missing: install Git for Windows (Git Bash) or set NB_BASH")
        f = tmp / f"step{i}.sh"
        f.write_text(script, encoding="utf-8", newline="\n")
        return [self.cfg.bash, f.as_posix() if IS_WIN else str(f)]

    def keep_symbols(self) -> None:
        dest = self.cfg.work_dir / "symbols" / self.job["platform"]
        for z in (self.src / "build").glob("debug-info-*.zip"):
            dest.mkdir(parents=True, exist_ok=True)
            shutil.copy2(z, dest / z.name)
            self.say(f"symbols kept: {dest / z.name} (the only way to read a stack trace of this build)")

    def execute(self) -> None:
        job, pump = self.job, self.pump
        assert pump is not None
        if not WORKFLOW_RE.match(str(job.get("workflow") or "")):
            raise StepFailed("workflow_invalid")
        sha = self.checkout(job["branch"])
        pump.set(commit_sha=sha, progress=5)
        wf = self.workflow(job["workflow"])
        minutes = int(wf.get("max_build_duration") or 120)
        self.deadline = min(self.deadline, time.monotonic() + minutes * 60)
        scripts = [s if isinstance(s, dict) else {"name": str(s)[:60], "script": str(s)} for s in wf.get("scripts") or []]
        tmp = Path(tempfile.mkdtemp(prefix="nb-runner-"))
        cm_env = tmp / "cm_env"
        cm_env.write_text("", encoding="utf-8")
        env = self.base_env(wf, sha, cm_env)
        pump.secrets = sorted(set(pump.secrets) | {s for s in (env.get("NB_UPLOAD_TOKEN"),
                                                                env.get("ANDROID_KEYSTORE_PASSWORD"),
                                                                env.get("ANDROID_KEY_PASSWORD")) if s and len(s) >= 4},
                              key=len, reverse=True)
        try:
            for i, step in enumerate(scripts):
                name = str(step.get("name") or f"step {i + 1}")
                script = str(step.get("script") or "")
                low = name.lower()
                status = "testing" if "gate" in low else ("uploading" if "upload" in low else "building")
                pump.set(status=status, progress=5 + int(90 * i / max(1, len(scripts))))
                if re.search(r"(^|\s)sudo\s", script):
                    self.say(f"skip: {name} (installs system packages with sudo — install them once on this "
                             f"machine, see tools/runner/README.md)")
                    continue
                self.say(f"step {i + 1}/{len(scripts)}: {name}")
                self.run(self.step_cmd(wf, script, tmp, i), f"step \"{name}\"", env=env)
                self.read_cm_env(cm_env, env)
            self.keep_symbols()
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

    def process(self) -> str:
        self.deadline = time.monotonic() + 6 * 3600
        with LogPump(self.api, self.job, self.cfg.secrets(), self.kill) as pump:
            self.pump = pump
            job = self.job
            self.say(f"runner {self.cfg.name} ({os_name()}): {job['platform']} {job['version']}+{job['build_number']}"
                     f" · workflow {job['workflow']} · branch {job['branch']} · gate {job.get('gate')}")
            ok, error = True, None
            try:
                self.execute()
            except JobGone:
                self.say("canceled from the dashboard")
                return "canceled"
            except StepFailed as exc:
                ok, error = False, str(exc)
            except Exception as exc:  # noqa: BLE001  a runner bug still ends the job
                ok, error = False, f"runner_error: {exc.__class__.__name__}: {pump.mask(str(exc))[:300]}"
            if error:
                self.say(f"FAILED: {pump.mask(error)}")
            pump.flush()
        if pump.canceled.is_set():
            return "canceled"
        try:
            res = self.api.post(f"/jobs/{job['id']}/finish", {"attempt": job["attempt"], "ok": ok,
                                                               "error": pump.mask(error or "")[:500] or None})
        except JobGone:
            return "canceled"
        return (res or {}).get("status") or ("ready" if ok else "failed")


# ── main ──────────────────────────────────────────────────────────────────────

def find_iscc() -> Optional[str]:
    """Inno Setup 6's compiler, looked up like scripts/release/package_windows.ps1 does (windows-website)."""
    found = os.environ.get("ISCC") or shutil.which("ISCC.exe") or shutil.which("ISCC")
    if found and Path(found).is_file():
        return found
    for root in (os.environ.get("LOCALAPPDATA", "") + "\\Programs", os.environ.get("ProgramFiles(x86)", ""),
                 os.environ.get("ProgramFiles", "")):
        p = Path(root) / "Inno Setup 6" / "ISCC.exe"
        if root and p.is_file():
            return str(p)
    return None


def check(cfg: Config) -> int:
    """--check: the setup and the token, without taking a job."""
    problems = []
    print(f"runner {cfg.name} on {os_name()} ({pf.platform()}), builds: {', '.join(cfg.platforms)}")
    print(f"server {cfg.api_url} · repo {re.sub(r'//[^@/]+@', '//****@', cfg.repo_url) or '—'} · work dir {cfg.work_dir}")
    if not cfg.token:
        problems.append("NB_BUILDER_TOKEN is not set (App versions › Build runner › New token)")
    if not cfg.repo_url:
        problems.append("NB_REPO_URL is not set and this folder has no git origin")
    try:
        import yaml  # noqa: F401
    except ImportError:
        problems.append("PyYAML is missing: py -m pip install pyyaml")
    if not (shutil.which("flutter.bat") if IS_WIN else shutil.which("flutter")):
        problems.append("flutter is not on PATH")
    if not shutil.which("git"):
        problems.append("git is not on PATH")
    if IS_WIN and not cfg.bash:
        problems.append("Git Bash was not found (install Git for Windows or set NB_BASH)")
    if IS_WIN and "windows" in cfg.platforms and not find_iscc():
        # windows-website packages the installer with Inno Setup (package_windows.ps1 also tries winget itself;
        # this tells the owner before a build fails on it)
        problems.append("Inno Setup 6 is missing (the Windows installer): winget install JRSoftware.InnoSetup")
    if "android" in cfg.platforms:
        if cfg.key_properties is None or not cfg.key_properties.is_file():
            problems.append("NB_KEY_PROPERTIES does not point to the Android release key.properties")
        else:
            p = read_properties(cfg.key_properties)
            missing = [k for k in ("storeFile", "storePassword", "keyAlias", "keyPassword") if not p.get(k)]
            if missing:
                problems.append(f"key.properties lacks {', '.join(missing)}")
    if cfg.token:
        req = urllib.request.Request(f"{cfg.api_url}/api/v1/builder/runner/jobs/0/report", method="POST",
                                     data=b'{"attempt": 0}', headers={"Authorization": f"Builder {cfg.token}",
                                                                      "Content-Type": "application/json"})
        try:
            urllib.request.urlopen(req, timeout=30)  # noqa: S310
        except urllib.error.HTTPError as e:
            if e.code == 401:
                problems.append("the server refuses the token (make a new one in App versions › Build runner)")
            elif e.code != 409:
                problems.append(f"the server answered HTTP {e.code}")
        except OSError as e:
            problems.append(f"the server is not reachable: {e}")
    for p in problems:
        print(f"  ✗ {p}")
    print("all good — start it without --check" if not problems else f"{len(problems)} thing(s) to fix")
    return 1 if problems else 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true", help="check the setup and the token, build nothing")
    ap.add_argument("--once", action="store_true", help="build at most one version, then exit")
    a = ap.parse_args(argv)
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    cfg = Config(load_env_file(HERE / "runner.env"))
    if a.check:
        return check(cfg)
    if not cfg.token:
        print("NB_BUILDER_TOKEN is not set: put it in tools/runner/runner.env (see README.md)", file=sys.stderr)
        return 2
    api = Api(cfg)
    print(f"nextbrain-runner {VERSION} \"{cfg.name}\" builds {', '.join(cfg.platforms)} — waiting for versions from "
          f"{cfg.api_url} (Ctrl+C stops)", flush=True)
    backoff = cfg.poll
    while True:
        try:
            job = api.claim()
            backoff = cfg.poll
        except KeyboardInterrupt:
            return 0
        except Exception as exc:  # noqa: BLE001  the server is down / unreachable: back off
            print(f"claim failed ({exc}); again in {backoff:.0f} s", file=sys.stderr, flush=True)
            if a.once:
                return 1
            time.sleep(backoff)
            backoff = min(300.0, backoff * 2)
            continue
        if job:
            result = Build(cfg, api, job).process()
            print(f"version {job['platform']} {job['version']}: {result}", flush=True)
            if a.once:
                return 0
            continue
        if a.once:
            return 0
        try:
            time.sleep(cfg.poll)
        except KeyboardInterrupt:
            return 0


if __name__ == "__main__":
    sys.exit(main())
