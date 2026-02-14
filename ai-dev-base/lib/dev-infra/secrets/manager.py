import os
import stat
from pathlib import Path
from typing import Optional


class SecretsManager:
    def __init__(self, base_dir: Optional[Path] = None):
        self.base_dir = Path(base_dir) if base_dir else Path.cwd()
        self.secrets_dir = self.base_dir / ".secrets"

    def _ensure_dir(self) -> None:
        if not self.secrets_dir.exists():
            self.secrets_dir.mkdir(parents=True, mode=0o700)
        else:
            os.chmod(self.secrets_dir, 0o700)

    def write_secret(self, name: str, value: str) -> Path:
        self._ensure_dir()
        secret_path = self.secrets_dir / name
        secret_path.write_text(value)
        os.chmod(secret_path, 0o600)
        return secret_path

    def read_secret(self, name: str) -> Optional[str]:
        secret_path = self.secrets_dir / name
        if not secret_path.exists():
            return None
        return secret_path.read_text().strip()

    def validate_permissions(self, name: str) -> bool:
        secret_path = self.secrets_dir / name
        if not secret_path.exists():
            return False
        mode = stat.S_IMODE(os.stat(secret_path).st_mode)
        return mode == 0o600
