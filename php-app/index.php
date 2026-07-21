<?php
declare(strict_types=1);

require_once __DIR__ . '/db.php';
send_no_store_headers();

try {
    $result = $conn->query('SELECT id, name, email FROM users ORDER BY id');
    $members = $result->fetch_all(MYSQLI_ASSOC);
    $result->free();
    $conn->close();
} catch (Throwable $error) {
    error_log('Unable to list members: ' . $error->getMessage());
    render_error_page(500, 'Unable to load members', 'The member list could not be loaded. Please try again.');
}
?>
<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>CNAS Assignment - Team Members</title>
    <link rel="stylesheet" href="assets/styles.css">
    <script src="assets/app.js" defer></script>
</head>
<body>
<main class="container">
    <header class="page-header">
        <div>
            <p class="eyebrow">CNAS Assignment - T01 Team 02</p>
            <h1>Team members</h1>
        </div>
        <a class="button" href="create.php">Add team member</a>
    </header>

    <?php if ($members === []): ?>
        <section class="message-card">
            <h2>No members yet</h2>
            <p>Add the first team member to get started.</p>
        </section>
    <?php else: ?>
        <div class="table-wrapper">
            <table>
                <thead>
                <tr>
                    <th scope="col">ID</th>
                    <th scope="col">Student name</th>
                    <th scope="col">Email</th>
                    <th scope="col">Actions</th>
                </tr>
                </thead>
                <tbody>
                <?php foreach ($members as $member): ?>
                    <tr>
                        <td><?= h($member['id']) ?></td>
                        <td><?= h($member['name']) ?></td>
                        <td><a href="mailto:<?= h($member['email']) ?>"><?= h($member['email']) ?></a></td>
                        <td class="actions">
                            <a href="update.php?id=<?= h($member['id']) ?>">Edit</a>
                            <form method="post" action="delete.php" class="delete-form"
                                  data-member-name="<?= h($member['name']) ?>">
                                <input type="hidden" name="id" value="<?= h($member['id']) ?>">
                                <input type="hidden" name="csrf_token" value="<?= h(csrf_token()) ?>">
                                <button class="link-button danger" type="submit">Delete</button>
                            </form>
                        </td>
                    </tr>
                <?php endforeach; ?>
                </tbody>
            </table>
        </div>
    <?php endif; ?>
</main>
</body>
</html>
