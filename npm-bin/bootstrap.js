const { spawnSync } = require("node:child_process");
const path = require("node:path");
const fs = require("node:fs");

const root = path.resolve(__dirname, "..");
const packageJson = require(path.join(root, "package.json"));
const packageVersion = packageJson.version;

const venvDir = path.join(root, ".aico-python");
const markerPath = path.join(venvDir, ".aico-installed-version");

const venvPython =
  process.platform === "win32"
    ? path.join(venvDir, "Scripts", "python.exe")
    : path.join(venvDir, "bin", "python");

function probe(command, prefix = []) {
  const result = spawnSync(
    command,
    [
      ...prefix,
      "-c",
      "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')"
    ],
    {
      encoding: "utf8",
      windowsHide: true
    }
  );

  if (result.status !== 0) return null;

  const value = String(result.stdout || "").trim();
  const parts = value.split(".").map(Number);

  if (
    parts.length >= 2 &&
    (parts[0] > 3 || (parts[0] === 3 && parts[1] >= 11))
  ) {
    return { command, prefix, version: value };
  }

  return null;
}

function findPython() {
  const candidates =
    process.platform === "win32"
      ? [
          ["py", ["-3"]],
          ["python", []],
          ["python3", []]
        ]
      : [
          ["python3", []],
          ["python", []]
        ];

  for (const [command, prefix] of candidates) {
    const found = probe(command, prefix);
    if (found) return found;
  }

  return null;
}

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: options.cwd || root,
    env: options.env || process.env,
    stdio: "inherit",
    windowsHide: false
  });

  if (result.error) {
    throw result.error;
  }

  if (result.status !== 0) {
    throw new Error(`${command} exited with code ${result.status}`);
  }

  return result;
}

function runtimeIsCurrent() {
  if (!fs.existsSync(venvPython)) return false;
  if (!fs.existsSync(markerPath)) return false;

  try {
    const installedVersion =
      fs.readFileSync(markerPath, "utf8").trim();

    return installedVersion === packageVersion;
  } catch {
    return false;
  }
}

function ensureVenv() {
  if (runtimeIsCurrent()) {
    return venvPython;
  }

  const python = findPython();

  if (!python) {
    throw new Error(
      "AI Company OS requires Python 3.11 or newer."
    );
  }

  if (!fs.existsSync(venvPython)) {
    console.log(
      `AI Company OS: creating Python environment with ${python.version}...`
    );

    run(
      python.command,
      [
        ...python.prefix,
        "-m",
        "venv",
        venvDir
      ]
    );
  }

  console.log(
    `AI Company OS: installing Python runtime ${packageVersion}...`
  );

  run(
    venvPython,
    [
      "-m",
      "pip",
      "install",
      "--disable-pip-version-check",
      "--upgrade",
      root
    ]
  );

  fs.writeFileSync(
    markerPath,
    packageVersion + "\n",
    "utf8"
  );

  return venvPython;
}

function findPowerShell() {
  const candidates =
    process.platform === "win32"
      ? ["pwsh.exe", "pwsh", "powershell.exe", "powershell"]
      : ["pwsh"];

  for (const candidate of candidates) {
    const result = spawnSync(
      candidate,
      [
        "-NoLogo",
        "-NoProfile",
        "-Command",
        "$PSVersionTable.PSVersion.ToString()"
      ],
      {
        stdio: "ignore",
        windowsHide: true
      }
    );

    if (result.status === 0) {
      return candidate;
    }
  }

  return null;
}

function runPowerShell(relativeScript, args = []) {
  const powerShell = findPowerShell();

  if (!powerShell) {
    throw new Error(
      "AI Company OS requires PowerShell."
    );
  }

  const script = path.join(root, relativeScript);

  const psArgs = [
    "-NoLogo",
    "-NoProfile"
  ];

  if (process.platform === "win32") {
    psArgs.push("-ExecutionPolicy", "Bypass");
  }

  psArgs.push(
    "-File",
    script,
    ...args
  );

  run(
    powerShell,
    psArgs,
    { cwd: process.cwd() }
  );
}

module.exports = {
  root,
  venvPython,
  ensureVenv,
  run,
  runPowerShell
};