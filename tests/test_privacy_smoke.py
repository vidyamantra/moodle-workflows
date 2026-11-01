import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / '.github/actions/privacy-smoke/run.sh'
FAKE_PHPUNIT = '''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
with open(os.environ['SMOKE_CALLS'], 'a') as stream:
    stream.write(json.dumps(args) + '\\n')
if os.environ.get('SMOKE_EXIT'):
    sys.exit(int(os.environ['SMOKE_EXIT']))
report = Path(args[args.index('--log-junit') + 1])
provider = args[-1].endswith('/provider_test.php')
mode = os.environ.get('SMOKE_MODE', '')
if mode == 'missing' or mode == 'missing_provider' and provider:
    sys.exit(0)
if mode == 'invalid':
    report.write_text('<broken>')
elif mode == 'skipped':
    report.write_text('<testsuites><testcase name="only"><skipped/></testcase></testsuites>')
elif mode == 'empty_registry' and not provider or mode == 'empty_provider' and provider:
    report.write_text('<testsuites/>')
else:
    report.write_text('<testsuites><testsuite><testcase name="actual"/></testsuite></testsuites>')
'''


class PrivacySmokeTest(unittest.TestCase):
    def run_smoke(self, *, public=False, legacy=False, mode='', status='', missing=False):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / 'moodle with spaces'
            root.mkdir()
            web = root / 'public' if public else root
            registry = web / 'admin/tool/dataprivacy/tests/metadata_registry_test.php'
            provider = web / ('privacy/tests/provider_test.php' if legacy
                              else 'privacy/tests/privacy/provider_test.php')
            for path in [registry, provider]:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('<?php // Test selector fixture.\n')
            if missing:
                provider.unlink()
            executable = root / 'vendor/bin/phpunit'
            executable.parent.mkdir(parents=True)
            executable.write_text(FAKE_PHPUNIT)
            executable.chmod(0o700)
            calls_file = Path(temporary) / 'calls.jsonl'
            environment = dict(os.environ, SMOKE_CALLS=str(calls_file),
                               SMOKE_MODE=mode, SMOKE_EXIT=status)
            result = subprocess.run(['bash', str(SCRIPT), str(root)], env=environment,
                                    capture_output=True, text=True, timeout=15)
            calls = [json.loads(line) for line in calls_file.read_text().splitlines()] if calls_file.exists() else []
            return result, calls

    def test_modern_flat_targets(self):
        result, calls = self.run_smoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([call[-1] for call in calls], [
            './admin/tool/dataprivacy/tests/metadata_registry_test.php',
            './privacy/tests/privacy/provider_test.php'])
        for call in calls:
            self.assertIn('--fail-on-risky', call)
            self.assertIn('--disallow-test-output', call)
            self.assertNotIn('--filter', call)
            self.assertNotIn('--testsuite', call)
        reports = [call[call.index('--log-junit') + 1] for call in calls]
        self.assertNotEqual(*reports)
        self.assertTrue(all(not Path(report).exists() for report in reports))

    def test_public_targets(self):
        result, calls = self.run_smoke(public=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([call[-1] for call in calls], [
            'public/admin/tool/dataprivacy/tests/metadata_registry_test.php',
            'public/privacy/tests/privacy/provider_test.php'])

    def test_legacy_provider_target(self):
        result, calls = self.run_smoke(legacy=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls[1][-1], './privacy/tests/provider_test.php')

    def test_missing_target_fails_before_phpunit(self):
        result, calls = self.run_smoke(missing=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, [])

    def test_each_smoke_requires_real_cases(self):
        for mode, count in [('empty_registry', 1), ('empty_provider', 2),
                            ('skipped', 1), ('invalid', 1), ('missing', 1), ('missing_provider', 2)]:
            with self.subTest(mode=mode):
                result, calls = self.run_smoke(mode=mode)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertEqual(len(calls), count)

    def test_upstream_failure_is_preserved(self):
        result, calls = self.run_smoke(status='7')
        self.assertEqual(result.returncode, 7)
        self.assertEqual(len(calls), 1)
