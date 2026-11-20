import contextlib
import importlib.util
import io
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock


spec = importlib.util.spec_from_file_location("bootstrap_secrets", Path(__file__).with_name("secrets.py"))
secrets = importlib.util.module_from_spec(spec)
spec.loader.exec_module(secrets)


class FakeVault:
    def __init__(self, data=None):
        self.data = data
        self.writes = []
        self.closed = False

    def request(self, method, path, payload=None, missing_ok=False):
        if method == "POST":
            self.writes.append(payload)
            self.data = payload["data"]
            return {}
        if self.data is None:
            return None
        return {"data": {"data": self.data, "metadata": {"version": 7}}}

    def close(self):
        self.closed = True


class SecretRecoveryTests(unittest.TestCase):
    def run_action(self, action, vault, local=None):
        with mock.patch.object(secrets, "Vault", return_value=vault), \
             mock.patch.object(secrets, "local_values", return_value=local or {}), \
             mock.patch("sys.argv", ["secrets.py", action]), \
             contextlib.redirect_stdout(io.StringIO()):
            secrets.main()

    def test_initial_store_uses_cas_and_readback(self):
        vault = FakeVault()
        self.run_action("store", vault, {"R2_SECRET_ACCESS_KEY": "private-input"})
        self.assertEqual(vault.writes, [{"data": {"r2-secret-access-key": "private-input"},
                                        "options": {"cas": 0}}])
        self.assertTrue(vault.closed)

    def test_store_preserves_remote_only_values_and_uses_current_version(self):
        vault = FakeVault({"android-keystore-base64": "signing-material"})
        self.run_action("store", vault, {"HOST_PASSWORD": "operator-input"})
        self.assertEqual(vault.data["android-keystore-base64"], "signing-material")
        self.assertEqual(vault.writes[0]["options"]["cas"], 7)

    def test_store_rejects_differing_values_without_disclosing_them(self):
        vault = FakeVault({"host-password": "newer-remote-value"})
        with self.assertRaises(RuntimeError) as error:
            self.run_action("store", vault, {"HOST_PASSWORD": "stale-local-value"})
        self.assertNotIn("newer-remote-value", str(error.exception))
        self.assertNotIn("stale-local-value", str(error.exception))
        self.assertEqual(vault.writes, [])
        self.assertTrue(vault.closed)

    def test_ci_check_never_reads_local_env(self):
        vault = FakeVault({"gh-admin-token": "private-input"})
        with mock.patch.object(secrets, "local_values", side_effect=AssertionError("CI read .env")), \
             mock.patch.object(secrets, "required_secrets", return_value={"GH_ADMIN_TOKEN"}), \
             mock.patch.object(secrets, "Vault", return_value=vault), \
             mock.patch("sys.argv", ["secrets.py", "check"]), \
             contextlib.redirect_stdout(io.StringIO()):
            secrets.main()

    def test_missing_secret_prevents_all_github_updates(self):
        vault = FakeVault({"gh-admin-token": "private-input"})
        with mock.patch.object(secrets, "required_secrets", return_value={"GH_ADMIN_TOKEN", "ANDROID_KEYSTORE_BASE64"}), \
             mock.patch.object(secrets.subprocess, "run") as run:
            with self.assertRaisesRegex(RuntimeError, "ANDROID_KEYSTORE_BASE64"):
                self.run_action("sync-github", vault)
            run.assert_not_called()

    def test_github_values_use_stdin_and_admin_auth_comes_from_vault(self):
        vault = FakeVault({"gh-admin-token": "vault-admin-input", "host-password": "private-input"})
        with mock.patch.object(secrets, "required_secrets", return_value={"GH_ADMIN_TOKEN", "HOST_PASSWORD"}), \
             mock.patch.object(secrets.subprocess, "run", return_value=subprocess.CompletedProcess([], 0)) as run:
            self.run_action("sync-github", vault)
            self.assertEqual(run.call_count, 2)
            for call in run.call_args_list:
                self.assertNotIn("private-input", call.args[0])
                self.assertNotIn("vault-admin-input", call.args[0])
                self.assertEqual(call.kwargs["env"]["GH_TOKEN"], "vault-admin-input")
                self.assertIn(call.kwargs["input"], {"vault-admin-input", "private-input"})

    def test_restore_refuses_existing_files_and_symlinks(self):
        with tempfile.TemporaryDirectory() as folder, mock.patch.object(secrets, "ROOT", Path(folder)):
            path = Path(folder) / ".env"
            path.write_text("keep-original")
            with self.assertRaises(FileExistsError):
                self.run_action("restore-env", FakeVault({"host-password": "private-input"}))
            self.assertEqual(path.read_text(), "keep-original")

    def test_env_restore_preserves_template_comments_without_blank_credentials(self):
        with tempfile.TemporaryDirectory() as folder, mock.patch.object(secrets, "ROOT", Path(folder)):
            (Path(folder) / ".env.example").write_text(
                '# First bootstrap stage\n# Used for SSH\nexport HOST_PASSWORD=""\n'
                '# Not yet available\nexport STRIPE_API_KEY=""\n')
            rendered = secrets.dotenv({"HOST_PASSWORD": "private-input", "EXTRA_INPUT": "extra"})
            self.assertIn("# First bootstrap stage\n# Used for SSH", rendered)
            self.assertIn('export HOST_PASSWORD="private-input"', rendered)
            self.assertNotIn('export STRIPE_API_KEY=', rendered)
            self.assertIn('export EXTRA_INPUT="extra"', rendered)

    def test_restore_refuses_symlink_even_when_replacement_is_requested(self):
        with tempfile.TemporaryDirectory() as folder, mock.patch.object(secrets, "ROOT", Path(folder)):
            target = Path(folder) / "original"
            target.write_text("keep-original")
            (Path(folder) / ".env").symlink_to(target)
            with mock.patch.object(secrets, "Vault", return_value=FakeVault({"host-password": "private-input"})), \
                 mock.patch("sys.argv", ["secrets.py", "restore-env", "--replace-existing"]):
                with self.assertRaises(OSError):
                    secrets.main()
            self.assertEqual(target.read_text(), "keep-original")


if __name__ == "__main__":
    unittest.main()
