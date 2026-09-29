#!/usr/bin/env node

const path = require("node:path");

const {
  ensureVenv,
  run,
  runPowerShell
} = require("./bootstrap");

function fail(message) {
  console.error(message);
  process.exit(1);
}

const args = process.argv.slice(2);
const command = args[0];

try {
  if (command === "install" || command === "init") {
    const target = path.resolve(
      args[1] || process.cwd()
    );

    const psArgs = [
      "-TargetProject",
      target
    ];

    if (args.includes("--force")) {
      psArgs.push("-Force");
    }

    runPowerShell(
      "scripts/install-existing-project.ps1",
      psArgs
    );

    const python = ensureVenv();

    run(
      python,
      [
        "-m",
        "company_os.cli.app",
        "use",
        target
      ],
      {
        cwd: target
      }
    );

    console.log("");
    console.log(
      `AI Company OS ready: ${target}`
    );

    process.exit(0);
  }

  if (command === "new") {
    const projectName = args[1];

    if (!projectName) {
      fail(
        "Usage: aico new <project-name> [destination]"
      );
    }

    const destination = path.resolve(
      args[2] || process.cwd()
    );

    runPowerShell(
      "scripts/new-project.ps1",
      [
        "-ProjectName",
        projectName,
        "-Destination",
        destination
      ]
    );

    const projectPath = path.join(
      destination,
      projectName
    );

    const python = ensureVenv();

    run(
      python,
      [
        "-m",
        "company_os.cli.app",
        "use",
        projectPath
      ],
      {
        cwd: projectPath
      }
    );

    console.log("");
    console.log(
      `AI Company OS project ready: ${projectPath}`
    );

    process.exit(0);
  }

  const python = ensureVenv();

  run(
    python,
    [
      "-m",
      "company_os.cli.app",
      ...args
    ],
    {
      cwd: process.cwd()
    }
  );
} catch (error) {
  console.error(
    `AI Company OS: ${error.message}`
  );
  process.exit(1);
}
