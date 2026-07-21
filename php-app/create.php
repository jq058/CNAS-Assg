<?php
declare(strict_types=1);

require_once __DIR__ . '/bootstrap.php';
require_once __DIR__ . '/database.php';
send_no_store_headers();

if (!in_array($_SERVER['REQUEST_METHOD'], ['GET', 'POST'], true)) {
    header('Allow: GET, POST');
    render_error_page(405, 'Method not allowed', 'Use the form to create a team member.');
}

$values = ['name' => '', 'email' => ''];
$errors = [];

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (!request_csrf_is_valid()) {
        render_error_page(403, 'Request rejected', 'The form expired or was submitted from another site. Please try again.');
    }

    [$values, $errors] = validate_member_input($_POST);
    if ($errors === []) {
        try {
            $conn = database_connection();
        } catch (Throwable $error) {
            error_log('Database connection failed while creating a member: ' . $error->getMessage());
            render_error_page(503, 'Temporarily unavailable', 'The database service is unavailable. Please try again shortly.');
        }

        try {
            $statement = $conn->prepare('INSERT INTO users (name, email) VALUES (?, ?)');
            $statement->bind_param('ss', $values['name'], $values['email']);
            $statement->execute();
            $statement->close();
            $conn->close();
            redirect_to_index();
        } catch (mysqli_sql_exception $error) {
            if ($error->getCode() === 1062) {
                $errors['email'] = 'That email address is already registered.';
            } else {
                error_log('Unable to create member: ' . $error->getMessage());
                render_error_page(500, 'Unable to create member', 'The member could not be saved. Please try again.');
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
    <title>Add team member</title>
    <link rel="stylesheet" href="assets/styles.css">
</head>
<body>
<main class="container form-card">
    <p class="eyebrow">CNAS Assignment - T01 Team 02</p>
    <h1>Add team member</h1>

    <?php if ($errors !== []): ?>
        <div class="error-summary" role="alert">
            <strong>Check the highlighted fields.</strong>
        </div>
    <?php endif; ?>

    <form method="post" action="create.php">
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
            <button class="button" type="submit">Create member</button>
            <a class="button secondary" href="index.php">Cancel</a>
        </div>
    </form>
</main>
</body>
</html>
