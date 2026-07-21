<?php
declare(strict_types=1);

function h(mixed $value): string
{
    return htmlspecialchars((string) $value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

function text_length(string $value): int
{
    if (function_exists('mb_strlen')) {
        return mb_strlen($value, 'UTF-8');
    }

    $count = preg_match_all('/./us', $value, $characters);
    return $count === false ? strlen($value) : $count;
}

/**
 * @return array{0: array{name: string, email: string}, 1: array<string, string>}
 */
function validate_member_input(array $input): array
{
    $values = [
        'name' => trim(is_string($input['name'] ?? null) ? $input['name'] : ''),
        'email' => trim(is_string($input['email'] ?? null) ? $input['email'] : ''),
    ];
    $errors = [];

    if ($values['name'] === '') {
        $errors['name'] = 'Enter the member name.';
    } elseif (preg_match('//u', $values['name']) !== 1) {
        $errors['name'] = 'The member name must be valid UTF-8 text.';
    } elseif (text_length($values['name']) > 100) {
        $errors['name'] = 'The member name must be 100 characters or fewer.';
    } elseif (preg_match('/[\x00-\x1F\x7F]/u', $values['name']) === 1) {
        $errors['name'] = 'The member name contains unsupported control characters.';
    }

    if ($values['email'] === '') {
        $errors['email'] = 'Enter the email address.';
    } elseif (strlen($values['email']) > 254) {
        $errors['email'] = 'The email address must be 254 characters or fewer.';
    } elseif (filter_var($values['email'], FILTER_VALIDATE_EMAIL) === false) {
        $errors['email'] = 'Enter a valid email address.';
    }

    return [$values, $errors];
}

function positive_integer(mixed $value): ?int
{
    if (is_int($value)) {
        return $value > 0 ? $value : null;
    }

    if (!is_string($value) || !preg_match('/^[1-9][0-9]*$/', $value)) {
        return null;
    }

    $validated = filter_var($value, FILTER_VALIDATE_INT, [
        'options' => ['min_range' => 1],
    ]);

    return $validated === false ? null : $validated;
}

function csrf_token_matches(array $session, mixed $submitted): bool
{
    $expected = $session['csrf_token'] ?? null;

    return is_string($expected)
        && $expected !== ''
        && is_string($submitted)
        && hash_equals($expected, $submitted);
}

function csrf_token(): string
{
    if (empty($_SESSION['csrf_token']) || !is_string($_SESSION['csrf_token'])) {
        $_SESSION['csrf_token'] = bin2hex(random_bytes(32));
    }

    return $_SESSION['csrf_token'];
}

function request_csrf_is_valid(): bool
{
    return csrf_token_matches($_SESSION, $_POST['csrf_token'] ?? null);
}

function send_no_store_headers(): void
{
    header('Cache-Control: no-store, max-age=0');
    header('Pragma: no-cache');
}

function redirect_to_index(): never
{
    header('Location: index.php', true, 303);
    exit;
}

function render_error_page(int $status, string $heading, string $message): never
{
    http_response_code($status);
    send_no_store_headers();
    header('Content-Type: text/html; charset=UTF-8');
    ?>
    <!doctype html>
    <html lang="en">
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title><?= h($status . ' - ' . $heading) ?></title>
        <link rel="stylesheet" href="/assets/styles.css">
    </head>
    <body>
    <main class="container message-card">
        <p class="status-code">Error <?= h($status) ?></p>
        <h1><?= h($heading) ?></h1>
        <p><?= h($message) ?></p>
        <p><a class="button secondary" href="index.php">Return to the member list</a></p>
    </main>
    </body>
    </html>
    <?php
    exit;
}
