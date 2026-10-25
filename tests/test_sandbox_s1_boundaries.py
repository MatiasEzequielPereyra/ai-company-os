"""Independent checks that S1 remains a pure library, not a sandbox backend."""

import ast
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
MODULES = ("puretypes.py", "model.py", "codecs.py")


@pytest.mark.parametrize("name", MODULES)
def test_pure_core_has_no_operational_imports_or_calls(name):
    source = ROOT / "src" / "company_os" / "sandbox" / name
    tree = ast.parse(source.read_text(encoding="utf-8"))
    forbidden_imports = {
        "os",
        "pathlib",
        "subprocess",
        "socket",
        "requests",
        "http",
        "urllib",
        "ctypes",
        "multiprocessing",
        "threading",
        "asyncio",
        "tempfile",
        "shutil",
        "time",
        "random",
        "secrets",
        "keyring",
        "winreg",
    }
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            assert not {a.name.split(".")[0] for a in node.names} & forbidden_imports
        if isinstance(node, ast.ImportFrom) and node.module:
            assert node.module.split(".")[0] not in forbidden_imports
        if isinstance(node, ast.Call):
            if isinstance(node.func, ast.Name):
                assert node.func.id not in {
                    "open",
                    "eval",
                    "exec",
                    "__import__",
                    "input",
                }
            if isinstance(node.func, ast.Attribute):
                assert node.func.attr not in {
                    "now",
                    "utcnow",
                    "uuid4",
                    "write_text",
                    "write_bytes",
                }


@pytest.mark.parametrize("name", MODULES)
def test_pure_core_is_not_wired_into_existing_runtime(name):
    # Package discovery can include the library. Existing runtime must not import
    # or execute it automatically merely because this slice exists.
    needle = "company_os.sandbox." + name[:-3]
    for source in (ROOT / "src" / "company_os").rglob("*.py"):
        if "sandbox" in source.parts:
            continue
        assert needle not in source.read_text(encoding="utf-8"), str(source)
