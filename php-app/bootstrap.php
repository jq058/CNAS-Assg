<?php
declare(strict_types=1);

require_once __DIR__ . '/functions.php';
require_once __DIR__ . '/session_store.php';

function environment_flag(string $name, bool $default): bool
{
    $value = getenv($name);
    if ($value === false || $value === '') {
        return $default;
    }

    $parsed = filter_var($value, FILTER_VALIDATE_BOOLEAN, FILTER_NULL_ON_FAILURE);
    return $parsed ?? $default;
}

function request_uses_https(): bool
{
    if (!empty($_SERVER['HTTPS']) && strtolower((string) $_SERVER['HTTPS']) !== 'off') {
        return true;
    }

    $forwardedProtocol = explode(',', (string) ($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? ''))[0];
    return strtolower(trim($forwardedProtocol)) === 'https';
}

function configure_session_storage(): void
{
    $handler = configured_session_handler();
    if ($handler === 'files') {
        ini_set('session.save_handler', 'files');
        ini_set('session.save_path', (string) (getenv('SESSION_SAVE_PATH') ?: '/tmp/php-sessions'));
        return;
    }

    $settings = redis_session_settings();
    ini_set('session.save_handler', 'redis');
    ini_set('session.save_path', redis_session_save_path($settings));
}

if (session_status() === PHP_SESSION_NONE) {
    try {
        configure_session_storage();
        ini_set('session.use_strict_mode', '1');
        ini_set('session.use_only_cookies', '1');
        ini_set('session.cookie_httponly', '1');
        ini_set('session.cookie_samesite', 'Lax');
        session_name('cnas_session');
        session_set_cookie_params([
            'lifetime' => 0,
            'path' => '/',
            'secure' => environment_flag('SESSION_COOKIE_SECURE', request_uses_https()),
            'httponly' => true,
            'samesite' => 'Lax',
        ]);

        if (!@session_start()) {
            throw new RuntimeException('Unable to start the application session.');
        }
    } catch (Throwable $error) {
        error_log('Session initialization failed: ' . $error->getMessage());
        render_error_page(503, 'Temporarily unavailable', 'The session service is unavailable. Please try again shortly.');
    }
}

csrf_token();
