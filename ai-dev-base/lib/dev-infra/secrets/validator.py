import stat
from pathlib import Path


def validate_secret_file(path: Path) -> bool:
    if not path.exists():
        return False
    mode = stat.S_IMODE(path.stat().st_mode)
    return mode == 0o600
