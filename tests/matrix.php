<?php
// Exercise the real matrix parser without a Moodle install or network access.

require __DIR__ . '/../vendor/autoload.php';

use Symfony\Component\Yaml\Yaml;

function check(bool $condition, string $message): void {
    if (!$condition) {
        throw new RuntimeException($message);
    }
}

function parse_matrix(array $supported, array $options = []): array {
    $workspace = sys_get_temp_dir() . '/moodle-matrix-' . bin2hex(random_bytes(8));
    mkdir($workspace);
    mkdir("$workspace/plugin");
    symlink(dirname(__DIR__), "$workspace/ci");
    $output = "$workspace/output";
    file_put_contents("$workspace/plugin/version.php", '<?php $plugin->component = "local_matrixfixture"; '
        . '$plugin->requires = 2024100700; $plugin->supported = ' . var_export($supported, true) . ';');
    $env = array_merge(getenv(), [
        'GITHUB_WORKSPACE' => $workspace,
        'GITHUB_OUTPUT' => $output,
        'filter' => '',
        'min_php' => '7.4',
        'disable_main' => '',
        'disable_master' => '',
        'disable_behat' => '',
        'disable_phpunit' => '',
    ], $options);
    try {
        // An unexpected updates API request fails rather than silently going online.
        $process = proc_open([PHP_BINARY, '-d', 'disable_functions=curl_init',
            __DIR__ . '/../.github/actions/parse-version/script.php'],
            [1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $pipes, null, $env);
        check(is_resource($process), 'Cannot start matrix parser');
        $stdout = stream_get_contents($pipes[1]);
        $stderr = stream_get_contents($pipes[2]);
        fclose($pipes[1]);
        fclose($pipes[2]);
        $status = proc_close($process);
        check($status === 0, "Parser failed: $stdout\n$stderr");
        check($stderr === '', "Parser warning: $stderr");
        $values = [];
        foreach (file($output, FILE_IGNORE_NEW_LINES) as $line) {
            [$name, $value] = explode('=', $line, 2);
            $values[$name] = $value;
        }
        foreach (['matrix', 'behat_matrix', 'phpunit_matrix'] as $name) {
            $values[$name] = json_decode($values[$name], true, 512, JSON_THROW_ON_ERROR)['include'];
        }
        return $values;
    } finally {
        unlink("$workspace/plugin/version.php");
        rmdir("$workspace/plugin");
        unlink("$workspace/ci");
        if (file_exists($output)) {
            unlink($output);
        }
        rmdir($workspace);
    }
}

$current = parse_matrix([405, 503]);
$branches = array_values(array_unique(array_column($current['matrix'], 'moodle-branch')));
check($branches === ['MOODLE_503_STABLE', 'MOODLE_502_STABLE', 'MOODLE_501_STABLE',
    'MOODLE_500_STABLE', 'MOODLE_405_STABLE'], '503 supported range must select stable 503, not moving main');
check($current['highest_moodle_branch'] === 'MOODLE_503_STABLE', 'Highest stable branch must be 503');
check($current['latest_pgsql_ver'] === '17', 'Highest stable PostgreSQL must meet the 503 floor');
check($current['highest_php'] === '8.4' && $current['lowest_php'] === '8.1', 'Retain older PHP floor');

$older = parse_matrix([405, 502]);
check(count($older['matrix']) === 16, 'Closed older support range must retain its four branches');
check($older['highest_moodle_branch'] === 'MOODLE_502_STABLE', 'Do not widen older plugin support');
check($older['latest_pgsql_ver'] === '16', 'Preserve older PostgreSQL selection');

$explicit = parse_matrix([405, 502], ['filter' => 'MOODLE_503_STABLE']);
check(count($explicit['matrix']) === 4, 'Explicit 503 must select both PHP and database variants');
$combinations = [];
foreach ($explicit['matrix'] as $row) {
    check($row['moodle-branch'] === 'MOODLE_503_STABLE', 'Explicit filter leaked another branch');
    check($row['pgsql-ver'] === '17' && $row['mariadb-ver'] === '11.4', 'Both DB services must meet 503 floors');
    check($row['node'] === '22', '503 Node selection changed');
    $combinations[] = $row['php'] . '/' . $row['database'];
}
sort($combinations);
check($combinations === ['8.3/mariadb', '8.3/pgsql', '8.4/mariadb', '8.4/pgsql'], 'Incomplete 503 combinations');

$restricted = parse_matrix([405, 503], ['filter' => 'MOODLE_503_STABLE', 'min_php' => '8.4']);
check(count($restricted['matrix']) === 2, 'PHP minimum must remove both older-PHP DB rows');
check(array_unique(array_column($restricted['matrix'], 'php')) === ['8.4'], 'PHP minimum was ignored');

$disabled = parse_matrix([503, 503], ['disable_behat' => 'true', 'disable_phpunit' => 'false']);
check($disabled['behat_matrix'] === [], 'Disabled Behat must stay empty');
check(count($disabled['phpunit_matrix']) === 4, 'String false must retain PHPUnit');

foreach (glob(__DIR__ . '/../.github/workflows/*.yml') as $file) {
    Yaml::parseFile($file);
}
echo "PASS: supported ranges, explicit branches, PHP floors, DB variants and disabled suites\n";
