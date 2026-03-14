<?php
require_once __DIR__ . '/db-config.php';

$conn = get_db_connection();
$message = '';

if ($conn) {
    // テーブル作成（初回のみ）
    mysqli_query($conn, "
        CREATE TABLE IF NOT EXISTS memos (
            id INT AUTO_INCREMENT PRIMARY KEY,
            title VARCHAR(200) NOT NULL,
            body TEXT,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ");

    // POST処理
    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        $action = $_POST['action'] ?? '';

        if ($action === 'add') {
            $title = $_POST['title'] ?? '';
            $body = $_POST['body'] ?? '';
            if ($title !== '') {
                $stmt = mysqli_prepare($conn, "INSERT INTO memos (title, body) VALUES (?, ?)");
                mysqli_stmt_bind_param($stmt, 'ss', $title, $body);
                mysqli_stmt_execute($stmt);
                mysqli_stmt_close($stmt);
                $message = 'Added.';
            }
        } elseif ($action === 'delete') {
            $id = (int)($_POST['id'] ?? 0);
            if ($id > 0) {
                $stmt = mysqli_prepare($conn, "DELETE FROM memos WHERE id = ?");
                mysqli_stmt_bind_param($stmt, 'i', $id);
                mysqli_stmt_execute($stmt);
                mysqli_stmt_close($stmt);
                $message = 'Deleted.';
            }
        }
    }

    // メモ一覧取得
    $memos = [];
    $result = mysqli_query($conn, "SELECT * FROM memos ORDER BY created_at DESC LIMIT 50");
    while ($row = mysqli_fetch_assoc($result)) {
        $memos[] = $row;
    }
}
?>
<!DOCTYPE html>
<html lang="ja">
<head>
    <meta charset="UTF-8">
    <title>Sample Memo App</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; max-width: 800px; margin: 40px auto; padding: 0 20px; background: #f5f5f5; }
        .card { background: white; border-radius: 8px; padding: 24px; margin: 16px 0; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #1a73e8; }
        h2 { color: #333; }
        input[type="text"], textarea { width: 100%; padding: 8px; margin: 4px 0 12px; border: 1px solid #ddd; border-radius: 4px; box-sizing: border-box; }
        textarea { height: 80px; }
        button { padding: 8px 20px; border: none; border-radius: 4px; cursor: pointer; font-size: 14px; }
        .btn-add { background: #1a73e8; color: white; }
        .btn-add:hover { background: #1557b0; }
        .btn-del { background: #ea4335; color: white; font-size: 12px; padding: 4px 12px; }
        .btn-del:hover { background: #c5221f; }
        .memo { border-bottom: 1px solid #eee; padding: 12px 0; }
        .memo:last-child { border-bottom: none; }
        .memo-title { font-weight: bold; font-size: 16px; }
        .memo-body { color: #555; margin: 4px 0; white-space: pre-wrap; }
        .memo-date { color: #999; font-size: 12px; }
        .memo-header { display: flex; justify-content: space-between; align-items: center; }
        .message { background: #e8f5e9; color: #2e7d32; padding: 8px 16px; border-radius: 4px; margin: 8px 0; }
        a { color: #1a73e8; }
        .ng { color: #ea4335; }
    </style>
</head>
<body>
    <h1>Sample Memo App</h1>
    <p><a href="/">&larr; Top</a></p>

    <?php if (!$conn): ?>
        <div class="card">
            <p class="ng">DB Connection Failed: <?= htmlspecialchars(mysqli_connect_error()) ?></p>
        </div>
    <?php else: ?>

        <?php if ($message): ?>
            <div class="message"><?= htmlspecialchars($message) ?></div>
        <?php endif; ?>

        <div class="card">
            <h2>New Memo</h2>
            <form method="POST">
                <input type="hidden" name="action" value="add">
                <label>Title</label>
                <input type="text" name="title" required placeholder="Enter title...">
                <label>Body</label>
                <textarea name="body" placeholder="Enter memo..."></textarea>
                <button type="submit" class="btn-add">Add</button>
            </form>
        </div>

        <div class="card">
            <h2>Memos (<?= count($memos) ?>)</h2>
            <?php if (empty($memos)): ?>
                <p>No memos yet. Add one above.</p>
            <?php else: ?>
                <?php foreach ($memos as $memo): ?>
                    <div class="memo">
                        <div class="memo-header">
                            <span class="memo-title"><?= htmlspecialchars($memo['title']) ?></span>
                            <form method="POST" style="display:inline;" onsubmit="return confirm('Delete?');">
                                <input type="hidden" name="action" value="delete">
                                <input type="hidden" name="id" value="<?= (int)$memo['id'] ?>">
                                <button type="submit" class="btn-del">Delete</button>
                            </form>
                        </div>
                        <?php if ($memo['body']): ?>
                            <div class="memo-body"><?= htmlspecialchars($memo['body']) ?></div>
                        <?php endif; ?>
                        <div class="memo-date"><?= htmlspecialchars($memo['created_at']) ?></div>
                    </div>
                <?php endforeach; ?>
            <?php endif; ?>
        </div>

    <?php endif; ?>
</body>
</html>
<?php if ($conn) mysqli_close($conn); ?>
