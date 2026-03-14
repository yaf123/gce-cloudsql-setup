<?php
/**
 * DB接続設定を /etc/myapp-db.conf から読み込む
 * パスワードはSecret Managerから取得済み
 */
function get_db_config(): array {
    $conf = [];
    $lines = file('/etc/myapp-db.conf', FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    foreach ($lines as $line) {
        if (strpos($line, '=') !== false) {
            [$key, $value] = explode('=', $line, 2);
            $conf[trim($key)] = trim($value);
        }
    }
    return $conf;
}

function get_db_connection(): mysqli|false {
    $conf = get_db_config();
    $conn = @mysqli_connect(
        $conf['DB_HOST'],
        $conf['DB_USER'],
        $conf['DB_PASSWORD'],
        $conf['DB_NAME'],
        (int)$conf['DB_PORT']
    );
    return $conn;
}
