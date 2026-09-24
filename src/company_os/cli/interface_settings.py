from __future__ import annotations

import json
import os
from pathlib import Path

from company_os.cli.i18n import (
    DEFAULT_LANGUAGE,
    SUPPORTED_LANGUAGES,
)


class InterfaceSettingsService:
    def __init__(
        self,
        path: Path | None = None,
    ) -> None:
        if path is None:
            appdata = os.environ.get(
                "APPDATA"
            )

            if appdata:
                root = Path(appdata)
            else:
                root = (
                    Path.home()
                    / ".config"
                )

            path = (
                root
                / "AICompanyOS"
                / "interface-settings.json"
            )

        self.path = Path(path)

    def load(self) -> dict:
        if not self.path.exists():
            return {
                "language": DEFAULT_LANGUAGE,
            }

        try:
            data = json.loads(
                self.path.read_text(
                    encoding="utf-8"
                )
            )

            if not isinstance(
                data,
                dict,
            ):
                return {
                    "language":
                    DEFAULT_LANGUAGE,
                }

            language = data.get(
                "language",
                DEFAULT_LANGUAGE,
            )

            if (
                language
                not in SUPPORTED_LANGUAGES
            ):
                language = DEFAULT_LANGUAGE

            data["language"] = language

            return data

        except (
            OSError,
            json.JSONDecodeError,
        ):
            return {
                "language": DEFAULT_LANGUAGE,
            }

    def load_language(self) -> str:
        return self.load()["language"]

    def save_language(
        self,
        language: str,
    ) -> None:
        if (
            language
            not in SUPPORTED_LANGUAGES
        ):
            raise ValueError(
                f"Unsupported language: "
                f"{language}"
            )

        data = self.load()
        data["language"] = language

        self.path.parent.mkdir(
            parents=True,
            exist_ok=True,
        )

        temporary = self.path.with_suffix(
            ".tmp"
        )

        temporary.write_text(
            json.dumps(
                data,
                indent=2,
                ensure_ascii=True,
            )
            + "\n",
            encoding="utf-8",
        )

        temporary.replace(
            self.path
        )
