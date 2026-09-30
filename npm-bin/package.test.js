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
    "scripts/update-runtime.ps1",
    "scripts/provider-router.ps1",
    "scripts/validate-engineering-plan-result.ps1,
        "scripts/validate-engineering-backlog-semantics.ps1",
    "scripts/run-writable-agent.ps1",
    "scripts/providers/invoke-ollama.ps1",
    ".codex/provider-config.json",
    ".codex/local-runtime-config.json",
    ".codex/writable-policy.json",
    "schemas/agent-result.schema.json",
    "schemas/engineering-plan-result.schema.json"
  ];

  for (const relative of required) {
    assert.equal(
      fs.existsSync(path.join(root, relative)),
      true,
      `Missing runtime file: ${relative}`
    );
  }
});


test("aico exposes the safe runtime update command", () => {
  const cli = fs.readFileSync(
    path.join(root, "npm-bin", "aico.js"),
    "utf8"
  );

  assert.match(cli, /command === "update"/);
  assert.match(cli, /scripts\/update-runtime\.ps1/);

  const updateStart = cli.indexOf('if (command === "update")');
  const updateEnd = cli.indexOf('if (command === "new")', updateStart);
  assert.notEqual(updateStart, -1);
  assert.notEqual(updateEnd, -1);

  const updateBlock = cli.slice(updateStart, updateEnd);
  const ensureIndex = updateBlock.indexOf("ensureVenv()");
  const updateScriptIndex = updateBlock.indexOf("scripts/update-runtime.ps1");

  assert.ok(
    ensureIndex >= 0 && ensureIndex < updateScriptIndex,
    "Package runtime must be validated before project files are updated"
  );
  assert.doesNotMatch(
    updateBlock,
    /company_os\.cli\.app[\s\S]*["']use["']/,
    "Runtime update must not change active-project selection"
  );
});
