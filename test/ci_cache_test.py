"""CI専用の一時領域と偽setupを使い、実際の復旧スクリプトを検証する。"""

import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"


class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="mail-weaver-cache-")
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name).resolve()
        self.runner = self.base / "runner with spaces"
        self.runner.mkdir()
        self.ci = self.runner / "mail-weaver-ci"
        self.scripts = self.base / "scripts"
        self.scripts.mkdir()
        shutil.copy2(SCRIPTS / "prepare-ci.sh", self.scripts)
        setup = self.scripts / "setup-ci.sh"
        setup.write_text('''#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "$*" >> "$CALLS"
if [[ $1 == --restore ]]; then
  [[ -f $2/valid ]] || exit 17
  exit 0
fi
[[ ! -e $1 && ! -L $1 ]] || exit 18
[[ ${FAIL_BUILD:-0} == 0 ]] || exit 19
mkdir -- "$1"
printf rebuilt > "$1/valid"
''')
        setup.chmod(0o755)
        self.calls = self.base / "calls"
        self.summary = self.base / "summary"
        self.env = dict(os.environ, RUNNER_TEMP=str(self.runner),
                        CALLS=str(self.calls), GITHUB_STEP_SUMMARY=str(self.summary))

    def run_prepare(self, hit, **overrides):
        return subprocess.run(
            ["bash", str(self.scripts / "prepare-ci.sh"), hit],
            env=dict(self.env, **overrides), capture_output=True, text=True)

    def test_miss_builds_once_and_clears_partial_restore(self):
        self.ci.mkdir()
        (self.ci / "partial").touch()
        result = self.run_prepare("false")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls.read_text().splitlines(), [str(self.ci)])
        self.assertFalse((self.ci / "partial").exists())
        self.assertIn("miss", self.summary.read_text())

    def test_hit_does_not_rebuild(self):
        self.ci.mkdir()
        (self.ci / "valid").write_text("cached")
        result = self.run_prepare("true")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls.read_text().splitlines(), [f"--restore {self.ci}"])
        self.assertEqual((self.ci / "valid").read_text(), "cached")
        self.assertIn("hit", self.summary.read_text())

    def test_invalid_cache_warns_and_rebuilds_once(self):
        self.ci.mkdir()
        (self.ci / "broken").touch()
        result = self.run_prepare("true")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("::warning::", result.stderr)
        self.assertEqual(self.calls.read_text().splitlines(),
                         [f"--restore {self.ci}", str(self.ci)])
        self.assertFalse((self.ci / "broken").exists())
        self.assertIn("recovered", self.summary.read_text())

    def test_rebuild_failure_propagates_without_retry(self):
        result = self.run_prepare("true", FAIL_BUILD="1")
        self.assertEqual(result.returncode, 19, result.stderr)
        self.assertEqual(len(self.calls.read_text().splitlines()), 2)
        self.assertFalse(self.summary.exists())

    def test_miss_build_failure_propagates(self):
        result = self.run_prepare("false", FAIL_BUILD="1")
        self.assertEqual(result.returncode, 19, result.stderr)
        self.assertEqual(self.calls.read_text().splitlines(), [str(self.ci)])

    def test_symlink_cleanup_preserves_target_and_other_data(self):
        outside = self.base / "outside"
        outside.mkdir()
        sentinel = outside / "keep"
        sentinel.write_text("user data")
        self.ci.symlink_to(outside, target_is_directory=True)
        result = self.run_prepare("false")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(sentinel.read_text(), "user data")
        self.assertFalse(self.ci.is_symlink())

    def test_invalid_arguments_never_invoke_setup(self):
        for hit, runner in [("unexpected", str(self.runner)),
                            ("false", "/"), ("false", "relative"), ("false", "")]:
            with self.subTest(hit=hit, runner=runner):
                result = self.run_prepare(hit, RUNNER_TEMP=runner)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.calls.exists())

    def test_setup_remains_a_failing_subprocess(self):
        # if関数呼び出しによるerrexit無効化で、途中失敗が成功に化けないこと。
        setup = self.scripts / "setup-ci.sh"
        setup.write_text('''#!/usr/bin/env bash
set -euo pipefail
if [[ $1 == --restore ]]; then
  false
  touch "$RUNNER_TEMP/should-not-exist"
fi
mkdir -- "$1"
''')
        result = self.run_prepare("true")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.runner / "should-not-exist").exists())
        self.assertIn("::warning::", result.stderr)


class ValidationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="mail-weaver-validation-")
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name).resolve()
        self.ci = self.base / "ci with spaces"
        for name in ["bin", "root", "tmp"]:
            (self.ci / name).mkdir(parents=True, exist_ok=True)
        self.opam = self.ci / "bin/opam"
        self.opam.write_text('''#!/usr/bin/env bash
set -eu
printf '%s\\n' "$*" >> "$OPAM_CALLS"
case "$*" in
  --version) echo 2.6.1 ;;
  'exec -- ocamlc -version') echo 5.4.1 ;;
  'exec -- dune --version') echo "${DUNE_VERSION:-3.24.2}"; exit "${VERSION_EXIT:-0}" ;;
  'exec -- ocamlformat --version') echo 0.29.0 ;;
  'var prefix') echo "${PREFIX_OVERRIDE:-$OPAMROOT/ci}" ;;
  'repository list --all --color=never') printf '%s\\n' "$FIXTURE_REPOSITORIES" ;;
  list*) printf '%s\\n' "${FIXTURE_PACKAGES:-dune 3.24.2}" ;;
  *) exit 99 ;;
esac
''')
        self.opam.chmod(0o755)
        # macOSでも同じ検証関数を実行するためのsha256sum互換shim。
        checksum = self.ci / "bin/sha256sum"
        checksum.write_text('''#!/usr/bin/env python3
import hashlib
from pathlib import Path
import sys
expected, filename = sys.stdin.read().strip().split("  ", 1)
sys.exit(0 if hashlib.sha256(Path(filename).read_bytes()).hexdigest() == expected else 1)
''')
        checksum.chmod(0o755)
        self.calls = self.base / "opam-calls"
        self.env = dict(os.environ, PATH=str(self.ci / "bin") + os.pathsep + os.environ["PATH"],
                        OPAMROOT=str(self.ci / "root"), OPAM_CALLS=str(self.calls),
                        FIXTURE_REPOSITORIES="default git+https://example.invalid/repo#pinned ci")
        self.digest = hashlib.sha256(self.opam.read_bytes()).hexdigest()
        result = self.validate("false")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.manifest = self.ci / "root/.mail-weaver-ci"
        self.calls.unlink()

    def validate(self, restore="true", **overrides):
        return subprocess.run(["bash", "-c", '''
source "$1"
ci_dir=$2
restore=$3
opam_sha256=$4
manifest="$ci_dir/root/.mail-weaver-ci"
script_sha=fixture-script-hash
repository_url=git+https://example.invalid/repo#pinned
opam_version=2.6.1
validate_environment
printf verified
''', "validate", str(SCRIPTS / "setup-ci.sh"), str(self.ci), restore, self.digest],
            env=dict(self.env, **overrides), capture_output=True, text=True)

    def assert_invalid(self, **overrides):
        result = self.validate(**overrides)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("verified", result.stdout)

    def test_valid_cache(self):
        result = self.validate()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("verified", result.stdout)

    def test_wrong_tool_version(self):
        self.assert_invalid(DUNE_VERSION="wrong")

    def test_correct_version_with_failed_command(self):
        self.assert_invalid(VERSION_EXIT="23")

    def test_manifest_mismatch_or_missing(self):
        for name in ["path", "setup-sha256", "repository-url", "repositories", "packages"]:
            target = self.manifest / name
            content = target.read_text()
            for replacement in ["wrong", None]:
                with self.subTest(name=name, replacement=replacement):
                    if replacement is None:
                        target.unlink()
                    else:
                        target.write_text(replacement)
                    self.assert_invalid()
                    target.write_text(content)

    def test_wrong_repository(self):
        self.assert_invalid(FIXTURE_REPOSITORIES="default https://example.invalid/wrong ci")

    def test_changed_installed_packages(self):
        self.assert_invalid(FIXTURE_PACKAGES="dune 0.0.0")

    def test_wrong_switch_prefix(self):
        self.assert_invalid(PREFIX_OVERRIDE="/some/other/switch")

    def test_checksum_failure_never_executes_opam(self):
        self.opam.write_text(self.opam.read_text() + "# corrupted\n")
        self.assert_invalid()
        self.assertFalse(self.calls.exists())


if __name__ == "__main__":
    unittest.main()
