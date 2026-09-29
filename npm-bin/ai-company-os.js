#!/usr/bin/env node

const { spawnSync } = require("node:child_process");
const path = require("node:path");
const fs = require("node:fs");

const root = path.resolve(__dirname, "..");

function findPython() {
  const candidates =
    process.platform === "win32"
      ? ["py", "python", "python3"]
      : ["python3", "python"];

  for (const candidate of candidates) {
    const args = candidate === "py" ? ["-3", "--version"] : ["--version"];

    const result = spawnSync(candidate, args, {
      stdio: "ignore"
    });

    if (result.status === 0) {
      return {
        command: candidate,
        prefix: candidate === "py" ? ["-3"] : []
      };
    }
  }

  return null;
}

const python = findPython();

if (!python) {
  console.error(
    "AI Company OS requires Python 3.11 or newer. Python was not found in PATH."
  );
  process.exit(1);
}

const src = path.join(root, "src");

const env = {
  ...process.env,
  PYTHONPATH: process.env.PYTHONPATH
    ? `${src}${path.delimiter}${process.env.PYTHONPATH}`
    : src
};

const args = [
  ...python.prefix,
  "-m",
  "company_os.cli.app",
  ...process.argv.slice(2)
];

const child = spawnSync(python.command, args, {
  cwd: process.cwd(),
  env,
  stdio: "inherit"
});

if (child.error) {
  console.error(child.error.message);
  process.exit(1);
}

process.exit(child.status ?? 1);
