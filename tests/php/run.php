<?php
declare(strict_types=1);

require_once __DIR__ . '/../../php-app/functions.php';

$tests = [];

function test(string $name, callable $callback): void
{
    global $tests;
    $tests[$name] = $callback;
}

function assert_same(mixed $expected, mixed $actual, string $message = ''): void
{
    if ($expected !== $actual) {
        throw new RuntimeException($message !== '' ? $message : sprintf(
            'Expected %s, got %s.',
            var_export($expected, true),
            var_export($actual, true)
        ));
    }
}

function assert_true(bool $condition, string $message = 'Expected condition to be true.'): void
{
    if (!$condition) {
        throw new RuntimeException($message);
    }
}

test('HTML output is encoded for text and attribute contexts', function (): void {
    assert_same('&lt;script&gt;&quot;&#039;&amp;', h('<script>"\'&'));
});

test('valid member input is trimmed and accepted', function (): void {
    [$values, $errors] = validate_member_input([
        'name' => '  Ada Lovelace  ',
        'email' => '  ada@example.test  ',
    ]);
    assert_same(['name' => 'Ada Lovelace', 'email' => 'ada@example.test'], $values);
    assert_same([], $errors);
});

test('invalid member input produces field errors', function (): void {
    [, $errors] = validate_member_input(['name' => '', 'email' => 'not-an-email']);
    assert_true(isset($errors['name']));
    assert_true(isset($errors['email']));
});

test('database field limits are enforced', function (): void {
    [, $errors] = validate_member_input([
        'name' => str_repeat('a', 101),
        'email' => str_repeat('b', 245) . '@example.test',
    ]);
    assert_true(isset($errors['name']));
    assert_true(isset($errors['email']));
});

test('UTF-8 names are counted as characters rather than bytes', function (): void {
    [$values, $errors] = validate_member_input([
        'name' => str_repeat("\xC3\xA9", 100),
        'email' => 'unicode@example.test',
    ]);
    assert_same([], $errors);
    assert_same(100, text_length($values['name']));
});

test('positive IDs reject coercion and invalid ranges', function (): void {
    assert_same(42, positive_integer('42'));
    assert_same(null, positive_integer('0'));
    assert_same(null, positive_integer('-1'));
    assert_same(null, positive_integer('1 OR 1=1'));
    assert_same(null, positive_integer(1.5));
});

test('CSRF comparison accepts only the exact string token', function (): void {
    $session = ['csrf_token' => 'known-secret-token'];
    assert_true(csrf_token_matches($session, 'known-secret-token'));
    assert_same(false, csrf_token_matches($session, 'KNOWN-secret-token'));
    assert_same(false, csrf_token_matches($session, null));
    assert_same(false, csrf_token_matches([], 'known-secret-token'));
});

$failures = 0;
foreach ($tests as $name => $callback) {
    try {
        $callback();
        fwrite(STDOUT, "PASS: {$name}\n");
    } catch (Throwable $error) {
        $failures++;
        fwrite(STDERR, "FAIL: {$name}\n  {$error->getMessage()}\n");
    }
}

fwrite(STDOUT, sprintf("%d test(s), %d failure(s).\n", count($tests), $failures));
exit($failures === 0 ? 0 : 1);
