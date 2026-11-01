#!/usr/bin/env bash
set -euo pipefail

cd "${1:-moodle}"
code_dir=.
if [ -f public/admin/tool/dataprivacy/tests/metadata_registry_test.php ]; then
    code_dir=public
fi
registry="$code_dir/admin/tool/dataprivacy/tests/metadata_registry_test.php"
provider="$code_dir/privacy/tests/privacy/provider_test.php"
if [ ! -f "$provider" ]; then
    provider="$code_dir/privacy/tests/provider_test.php"
fi
for target in "$registry" "$provider"; do
    if [ ! -f "$target" ]; then
        printf 'Missing core privacy test: %s\n' "$target" >&2
        exit 1
    fi
done

reports=$(mktemp -d)
trap 'rm -rf "$reports"' EXIT
index=0
for target in "$registry" "$provider"; do
    index=$((index + 1))
    report="$reports/$index.xml"
    vendor/bin/phpunit --fail-on-risky --disallow-test-output --log-junit "$report" "$target"
    php -r '
        if (!is_file($argv[1])) {
            fwrite(STDERR, "Missing privacy JUnit report\n");
            exit(1);
        }
        $xml = new DOMDocument();
        if (!$xml->load($argv[1], LIBXML_NONET)) {
            fwrite(STDERR, "Invalid privacy JUnit report\n");
            exit(1);
        }
        $executed = 0;
        foreach ($xml->getElementsByTagName("testcase") as $case) {
            if ($case->getElementsByTagName("skipped")->length === 0) {
                ++$executed;
            }
        }
        if ($executed === 0) {
            fwrite(STDERR, "Privacy smoke executed zero non-skipped test cases\n");
            exit(1);
        }
        echo "Privacy smoke executed $executed non-skipped test cases\n";
    ' "$report"
done
