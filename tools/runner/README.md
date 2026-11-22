# Build runner — build app versions on your own computer, for free (D-146)

The runner builds the versions you create in **Dashboard › Services › App versions (build & publish) › New version**
with **Build on: My computer (free)**. It runs the same workflow from `codemagic.yaml` that Codemagic would run, on
your machine, and uploads the files to our server. From there the version is published, offered for download and rolled
back exactly like one built on Codemagic.

| Machine | Builds |
|---|---|
| Windows PC | Windows, Android, web |
| Linux PC, or WSL (Ubuntu) on the Windows PC | Linux, Android, web |

Google Play and App Store uploads still go through Codemagic. An iPhone build needs a Mac and a paid Apple account
anyway, so iPhone users keep the web app.

## One-time setup on a Windows PC

1. **Tools.** Install these and make sure they're on PATH:
   - Flutter 3.47.7 (the version in `codemagic.yaml`)
   - Git for Windows, which includes Git Bash
   - Python 3.9 or newer
   - Android Studio, for the Android SDK and JDK. Run `flutter doctor --android-licenses` once.
   - Visual Studio 2022 Community with the **Desktop development with C++** workload. Only needed for Windows builds.
   - Inno Setup 6 (`winget install JRSoftware.InnoSetup`), which makes the Windows installer. Only needed for Windows
     builds; `scripts/release/package_windows.ps1` installs it with winget itself when it is missing, and `--check`
     reports it.

   Then install the one Python package the runner needs:
   ```
   py -m pip install pyyaml
   ```
   `flutter doctor` should show no red items for the platforms you build.

2. **The Android release key.** The key signs every APK, and phones only accept an update signed with the same key.
   **If you already have the release keystore** whose SHA-256 is in `web/.well-known/assetlinks.json` (`74:2C:D5:…`),
   use it and skip to `key.properties` below. Check a keystore with `keytool -list -v -keystore <file>`. Otherwise,
   create one once:
   ```
   "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -genkey -v -keystore C:\alfaheem-keys\alfaheem-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias nextbrain
   ```
   Next to it, create `C:\alfaheem-keys\key.properties`:
   ```
   storeFile=alfaheem-release.jks
   storePassword=<the password you chose>
   keyAlias=nextbrain
   keyPassword=<the key password>
   ```
   Keep this folder **outside the repository** and back up the `.jks` and the passwords, for example in a password
   manager. If you lose the key, people who installed the APK from the website can't update to a new one.
   If you later move Android to Google Play, use this same key as the upload key. A **new** key also needs its SHA-256
   in `web/.well-known/assetlinks.json`, so that share links keep opening the app, and in the Firebase Android app.

3. **The token.** In App versions, find the **Build runner** card and press **Create the token** (or **New token**).
   It is shown once.

4. **The settings.** Copy `tools/runner/runner.env.example` to `tools/runner/runner.env`; git ignores that file. Fill in
   `NB_BUILDER_TOKEN` and `NB_KEY_PROPERTIES`.

5. **Check the setup.**
   ```
   py tools\runner\nextbrain_runner.py --check
   ```
   It lists anything missing and makes sure the server accepts the token.

## Running it

```
py tools\runner\nextbrain_runner.py
```

Leave the window open. It waits for versions, builds them one at a time, and prints the same log the dashboard shows.
Ctrl+C stops it. A version created while the runner is off waits in the queue and starts as soon as the runner is on.
If the computer goes off in the middle of a build, the version fails with "runner stopped reporting"; press **Retry**.

To have it start with Windows, use Task Scheduler: create a task that runs at log on, with the program `py`, the
arguments `tools\runner\nextbrain_runner.py`, and the repository folder as the start folder.

The runner works in its own clone (`~/nextbrain-runner/src` by default), not in your checkout, so your work is never
touched. The debug symbols of every build are kept in `~/nextbrain-runner/symbols/<platform>/`. Keep them: they are the
only way to read a crash stack trace of that build (`flutter symbolize`).

## Linux / WSL

WSL is the easiest way to get Linux builds on the same PC. In PowerShell, run `wsl --install -d Ubuntu`, then do the
following inside Ubuntu:

```bash
sudo apt-get install -y git curl unzip xz-utils zip python3 python3-yaml clang cmake ninja-build pkg-config \
  libgtk-3-dev liblzma-dev libstdc++-12-dev libsecret-1-dev libjsoncpp-dev dpkg-dev libasound2-dev libpulse-dev \
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev
# Flutter 3.47.7 into ~/flutter (flutter.dev › Linux install), then:
flutter config --enable-linux-desktop
git clone <the app repository> ~/nextbrain-front && cd ~/nextbrain-front
cp tools/runner/runner.env.example tools/runner/runner.env   # the token; NB_RUNNER_PLATFORMS=linux if Windows builds the rest
python3 tools/runner/nextbrain_runner.py --check && python3 tools/runner/nextbrain_runner.py
```

The `codemagic.yaml` step that installs those packages with `sudo` is skipped on a runner. That's why you install
them once by hand above.

Two runners at once are fine, for example Windows and WSL. Each takes only the platforms it builds, and both use the
same token.

## How it works

The runner talks to these routes (server side: `../back/services/app_release_runner.py`, `docs/app_releases_runner.md`):

- `POST /api/v1/builder/runner/claim` with `{name, os, platforms, version}` returns the oldest queued version this
  machine builds, or 204 when there is nothing to build.
- `POST /api/v1/builder/runner/jobs/{id}/report` sends log lines, status and progress, and doubles as the heartbeat.
  A 409 means the version was canceled in the dashboard, and the runner stops the build.
- `POST /api/v1/builder/runner/jobs/{id}/finish` reports ok or the error.

For each job, the runner:

1. Checks out the version's branch in its own clone and reads `codemagic.yaml` at that commit.
2. Sets the job's `NB_*` variables (with the per-version upload token), the workflow's `vars`, `CM_BUILD_DIR`,
   `CM_BRANCH` and `CM_ENV` (lines a step appends there become variables of the later steps), and the
   `ANDROID_KEYSTORE_*` variables from your `key.properties` when the workflow signs Android.
3. Runs every script step: bash (Git Bash on Windows), or PowerShell for the Windows workflow. Git Bash has no `zip`,
   so `zip_shim.py` stands in for it.

The workflow's own last step, `scripts/release/upload_artifacts.sh`, uploads the files. Secrets are masked in every
line sent to the server.
