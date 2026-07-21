<?php
declare(strict_types=1);

require_once __DIR__ . '/db.php';
send_no_store_headers();

if (!in_array($_SERVER['REQUEST_METHOD'], ['GET', 'POST'], true)) {
    header('Allow: GET, POST');
    render_error_page(405, 'Method not allowed', 'Use the edit form to update a team member.');
}

$id = positive_integer($_GET['id'] ?? null);
if ($id === null) {
    render_error_page(400, 'Invalid member ID', 'Choose a member from the member list and try again.');
}

try {
    $statement = $conn->prepare('SELECT name, email FROM users WHERE id = ?');
    $statement->bind_param('i', $id);
    $statement->execute();
    $member = $statement->get_result()->fetch_assoc();
    $statement->close();
} catch (Throwable $error) {
    error_log('Unable to load member: ' . $error->getMessage());
    render_error_page(500, 'Unable to load member', 'The member record could not be loaded. Please try again.');
}

if (!is_array($member)) {
    render_error_page(404, 'Member not found', 'The requested member may already have been removed.');
}

$values = ['name' => (string) $member['name'], 'email' => (string) $member['email']];
$errors = [];

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (!request_csrf_is_valid()) {
        render_error_page(403, 'Request rejected', 'The form expired or was submitted from another site. Please try again.');
    }

    [$values, $errors] = validate_member_input($_POST);
    if ($errors === []) {
        try {
            $statement = $conn->prepare('UPDATE users SET name = ?, email = ? WHERE id = ?');
            $statement->bind_param('ssi', $values['name'], $values['email'], $id);
            $statement->execute();
            $statement->close();
            $conn->close();
            redirect_to_index();
        } catch (mysqli_sql_exception $error) {
            if ($error->getCode() === 1062) {
                $errors['email'] = 'That email address is already registered.';
            } else {
                error_log('Unable to update member: ' . $error->getMessage());
                render_error_page(500, 'Unable to update member', 'The member could not be saved. Please try again.');
            }
        }
    }
}
?>
<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Edit team member</title>
    <link rel="stylesheet" href="assets/styles.css">
</head>
<body>
<main class="container form-card">
    <p class="eyebrow">CNAS Assignment - T01 Team 02</p>
    <h1>Edit team member</h1>

    <?php if ($errors !== []): ?>
        <div class="error-summary" role="alert">
            <strong>Check the highlighted fields.</strong>
        </div>
    <?php endif; ?>

    <form method="post" action="update.php?id=<?= h($id) ?>">
        <input type="hidden" name="csrf_token" value="<?= h(csrf_token()) ?>">

        <div class="field">
            <label for="name">Member name</label>
            <input id="name" name="name" maxlength="100" autocomplete="name" required
                   value="<?= h($values['name']) ?>" <?= isset($errors['name']) ? 'aria-invalid="true" aria-describedby="name-error"' : '' ?>>
            <?php if (isset($errors['name'])): ?>
                <p class="field-error" id="name-error"><?= h($errors['name']) ?></p>
            <?php endif; ?>
        </div>

        <div class="field">
            <label for="email">Email address</label>
            <input id="email" name="email" type="email" maxlength="254" autocomplete="email" required
                   value="<?= h($values['email']) ?>" <?= isset($errors['email']) ? 'aria-invalid="true" aria-describedby="email-error"' : '' ?>>
            <?php if (isset($errors['email'])): ?>
                <p class="field-error" id="email-error"><?= h($errors['email']) ?></p>
            <?php endif; ?>
        </div>

        <div class="form-actions">
            <button class="button" type="submit">Save changes</button>
            <a class="button secondary" href="index.php">Cancel</a>
        </div>
    </form>
</main>
</body>
</html>
