import os
import stat
import tempfile
import unittest
from pathlib import Path

from secrets.manager import SecretsManager


class SecretsContractTests(unittest.TestCase):
    def test_secrets_permissions_contract(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            base_dir = Path(temp_dir)
            manager = SecretsManager(base_dir=base_dir)
            manager.write_secret("test_service", "secret_value")

            secret_path = base_dir / ".secrets" / "test_service"
            mode = stat.S_IMODE(os.stat(secret_path).st_mode)
            self.assertEqual(mode, 0o600)


if __name__ == "__main__":
    unittest.main()
