<?php
require_once __DIR__ . '/db-config.php';

$hostname = gethostname();
$server_ip = $_SERVER['SERVER_ADDR'] ?? 'unknown';
$php_version = phpversion();
?>
<!DOCTYPE html>
<html lang="ja">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>MyApp - GCE + Cloud SQL</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; max-width: 800px; margin: 40px auto; padding: 0 20px; background: #f5f5f5; }
        .card { background: white; border-radius: 8px; padding: 24px; margin: 16px 0; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #1a73e8; }
        h2 { color: #333; border-bottom: 2px solid #1a73e8; padding-bottom: 8px; }
        table { width: 100%; border-collapse: collapse; }
        td { padding: 8px 12px; border-bottom: 1px solid #eee; }
        td:first-child { font-weight: bold; color: #555; width: 40%; }
        .status-ok { color: #34a853; font-weight: bold; }
        .status-ng { color: #ea4335; font-weight: bold; }
        a { color: #1a73e8; text-decoration: none; }
        a:hover { text-decoration: underline; }
        nav { margin: 16px 0; }
        nav a { margin-right: 16px; padding: 8px 16px; background: #1a73e8; color: white; border-radius: 4px; }
        nav a:hover { background: #1557b0; text-decoration: none; }
    </style>
</head>
<body>
    <h1>MyApp - GCE + Cloud SQL Demo</h1>

    <nav>
        <a href="/">Top</a>
        <a href="/db-check.php">DB Check</a>
        <a href="/db-sample.php">Sample App</a>
    </nav>

    <div class="card">
        <h2>Server Info</h2>
        <table>
            <tr><td>Hostname</td><td><?= htmlspecialchars($hostname) ?></td></tr>
            <tr><td>Server IP</td><td><?= htmlspecialchars($server_ip) ?></td></tr>
            <tr><td>PHP Version</td><td><?= htmlspecialchars($php_version) ?></td></tr>
            <tr><td>OS</td><td><?= htmlspecialchars(php_uname()) ?></td></tr>
            <tr><td>Time</td><td><?= date('Y-m-d H:i:s T') ?></td></tr>
        </table>
    </div>

    <div class="card">
        <h2>DB Connection</h2>
        <?php
        $conn = get_db_connection();
        if ($conn) {
            echo '<p class="status-ok">Connected</p>';
            echo '<table>';
            echo '<tr><td>MySQL Version</td><td>' . htmlspecialchars(mysqli_get_server_info($conn)) . '</td></tr>';
            $conf = get_db_config();
            echo '<tr><td>Database</td><td>' . htmlspecialchars($conf['DB_NAME']) . '</td></tr>';
            echo '<tr><td>User</td><td>' . htmlspecialchars($conf['DB_USER']) . '</td></tr>';
            echo '<tr><td>Host</td><td>' . htmlspecialchars($conf['DB_HOST']) . ':' . htmlspecialchars($conf['DB_PORT']) . '</td></tr>';
            echo '</table>';
            mysqli_close($conn);
        } else {
            echo '<p class="status-ng">Connection Failed: ' . htmlspecialchars(mysqli_connect_error()) . '</p>';
        }
        ?>
    </div>
</body>
</html>
