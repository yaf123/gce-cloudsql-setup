<?php
require_once __DIR__ . '/db-config.php';
header('Content-Type: text/html; charset=UTF-8');
?>
<!DOCTYPE html>
<html lang="ja">
<head>
    <meta charset="UTF-8">
    <title>DB Check</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; max-width: 800px; margin: 40px auto; padding: 0 20px; background: #f5f5f5; }
        .card { background: white; border-radius: 8px; padding: 24px; margin: 16px 0; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #1a73e8; }
        h2 { color: #333; }
        .ok { color: #34a853; font-weight: bold; }
        .ng { color: #ea4335; font-weight: bold; }
        table { width: 100%; border-collapse: collapse; margin-top: 12px; }
        th, td { padding: 8px 12px; text-align: left; border-bottom: 1px solid #eee; }
        th { background: #f8f9fa; }
        a { color: #1a73e8; }
        pre { background: #f8f9fa; padding: 12px; border-radius: 4px; overflow-x: auto; }
    </style>
</head>
<body>
    <h1>DB Connection Check</h1>
    <p><a href="/">&larr; Top</a></p>

    <div class="card">
        <h2>1. Cloud SQL Auth Proxy Status</h2>
        <?php
        $proxy_status = shell_exec('systemctl is-active cloud-sql-proxy 2>&1');
        $is_running = trim($proxy_status) === 'active';
        echo $is_running
            ? '<p class="ok">Cloud SQL Auth Proxy: Running</p>'
            : '<p class="ng">Cloud SQL Auth Proxy: ' . htmlspecialchars(trim($proxy_status)) . '</p>';
        ?>
    </div>

    <div class="card">
        <h2>2. DB Connection Test</h2>
        <?php
        $conn = get_db_connection();
        if ($conn) {
            echo '<p class="ok">Connection: OK</p>';

            // データベース一覧
            echo '<h3>Databases</h3><table><tr><th>Database Name</th></tr>';
            $result = mysqli_query($conn, 'SHOW DATABASES');
            while ($row = mysqli_fetch_array($result)) {
                echo '<tr><td>' . htmlspecialchars($row[0]) . '</td></tr>';
            }
            echo '</table>';

            // テーブル一覧
            $conf = get_db_config();
            echo '<h3>Tables in ' . htmlspecialchars($conf['DB_NAME']) . '</h3>';
            $result = mysqli_query($conn, 'SHOW TABLES');
            if (mysqli_num_rows($result) > 0) {
                echo '<table><tr><th>Table Name</th></tr>';
                while ($row = mysqli_fetch_array($result)) {
                    echo '<tr><td>' . htmlspecialchars($row[0]) . '</td></tr>';
                }
                echo '</table>';
            } else {
                echo '<p>No tables yet.</p>';
            }

            mysqli_close($conn);
        } else {
            echo '<p class="ng">Connection Failed: ' . htmlspecialchars(mysqli_connect_error()) . '</p>';
            echo '<pre>Hint: Cloud SQL Auth Proxy が起動しているか確認してください</pre>';
        }
        ?>
    </div>
</body>
</html>
