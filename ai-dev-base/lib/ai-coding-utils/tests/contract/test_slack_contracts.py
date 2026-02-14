import os
import stat
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from slack import notifier as sn
from slack import cli as slack_cli


class SlackContractTests(unittest.TestCase):
    def test_rate_limiter_contract(self):
        limiter = sn.RateLimiter(max_requests=30, window_seconds=60)
        for _ in range(30):
            self.assertTrue(limiter.allow())
        self.assertFalse(limiter.allow())

    def test_secrets_permissions_contract(self):
        original_base = os.environ.get("AI_CODING_UTILS_BASE")
        try:
            with tempfile.TemporaryDirectory() as temp_dir:
                base_dir = Path(temp_dir)
                os.environ["AI_CODING_UTILS_BASE"] = str(base_dir)

                success = sn.init_secrets_file(base_dir=base_dir)
                self.assertTrue(success)

                secrets_file = base_dir / ".secrets" / "slack_webhook"
                self.assertTrue(secrets_file.exists())

                mode = stat.S_IMODE(os.stat(secrets_file).st_mode)
                self.assertEqual(mode, sn.REQUIRED_FILE_MODE)
        finally:
            if original_base is None:
                os.environ.pop("AI_CODING_UTILS_BASE", None)
            else:
                os.environ["AI_CODING_UTILS_BASE"] = original_base

    def test_slack_notifier_send_and_rate_limit(self):
        config = sn.SlackConfig(webhook_url="https://hooks.slack.com/services/T000/B000/XXXX")
        notifier = sn.SlackNotifier(config)
        notifier.rate_limiter = sn.RateLimiter(max_requests=1, window_seconds=60)

        class DummyResponse:
            status_code = 200

        with mock.patch("slack.notifier.requests.post", return_value=DummyResponse()):
            self.assertTrue(notifier.send("hello"))
            self.assertFalse(notifier.send("second"))

    def test_slack_cli_check_exit_codes(self):
        original_base = os.environ.get("AI_CODING_UTILS_BASE")
        original_env = os.environ.get("SLACK_WEBHOOK_URL")
        original_argv = os.sys.argv[:]

        try:
            with tempfile.TemporaryDirectory() as temp_dir:
                base_dir = Path(temp_dir)
                os.environ["AI_CODING_UTILS_BASE"] = str(base_dir)

                os.environ.pop("SLACK_WEBHOOK_URL", None)
                os.sys.argv = ["slack.cli", "check"]
                with self.assertRaises(SystemExit) as cm:
                    slack_cli.main()
                self.assertEqual(cm.exception.code, 1)

                os.environ["SLACK_WEBHOOK_URL"] = "https://hooks.slack.com/services/T000/B000/XXXX"
                os.sys.argv = ["slack.cli", "check"]
                with self.assertRaises(SystemExit) as cm:
                    slack_cli.main()
                self.assertEqual(cm.exception.code, 0)
        finally:
            if original_base is None:
                os.environ.pop("AI_CODING_UTILS_BASE", None)
            else:
                os.environ["AI_CODING_UTILS_BASE"] = original_base
            if original_env is None:
                os.environ.pop("SLACK_WEBHOOK_URL", None)
            else:
                os.environ["SLACK_WEBHOOK_URL"] = original_env
            os.sys.argv = original_argv


if __name__ == "__main__":
    unittest.main()
