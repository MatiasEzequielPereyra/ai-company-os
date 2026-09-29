const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..");

test("npm package contains required AI Company OS runtime", () => {
  const required = [
    "pyproject.toml",
    "src/company_os/cli/app.py",
    "scripts/install-existing-project.ps1",
    "scripts/new-project.ps1",
    "scripts/provider-router.ps1",
    "scripts/run-writable-agent.ps1",
    "scripts/providers/invoke-ollama.ps1",
    ".codex/provider-config.json",
    ".codex/local-runtime-config.json",
    ".codex/writable-policy.json",
    "schemas/agent-result.schema.json"
  ];

  for (const relative of required) {
    assert.equal(
      fs.existsSync(path.join(root, relative)),
      true,
      `Missing runtime file: ${relative}`
    );
  }
});
