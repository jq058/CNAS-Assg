<?php
declare(strict_types=1);

function application_environment(): string
{
    return strtolower((string) (getenv('APP_ENV') ?: 'production'));
}

function configured_session_handler(): string
{
    $configured = getenv('SESSION_HANDLER');
    if ($configured !== false && $configured !== '') {
        $handler = strtolower($configured);
    } elseif (getenv('REDIS_HOST') !== false && getenv('REDIS_HOST') !== '') {
        $handler = 'redis';
    } elseif (in_array(application_environment(), ['local', 'development', 'test'], true)) {
        $handler = 'files';
    } else {
        throw new RuntimeException('SESSION_HANDLER must be configured in production.');
    }

    if (!in_array($handler, ['files', 'redis'], true)) {
        throw new RuntimeException('Unsupported session handler.');
    }
    if ($handler === 'files' && !in_array(application_environment(), ['local', 'development', 'test'], true)) {
        throw new RuntimeException('File-backed sessions are only allowed in an explicit local or test environment.');
    }

    return $handler;
}

/**
 * @return array{host: string, port: int, database: int, password: string, timeout: float}
 */
function redis_session_settings(): array
{
    if (!extension_loaded('redis')) {
        throw new RuntimeException('Redis session handling is configured but the extension is unavailable.');
    }

    $host = (string) (getenv('REDIS_HOST') ?: 'redis');
    if (preg_match('/^[A-Za-z0-9.-]+$/', $host) !== 1) {
        throw new RuntimeException('Invalid Redis host configuration.');
    }

    $port = filter_var(getenv('REDIS_PORT') ?: '6379', FILTER_VALIDATE_INT, [
        'options' => ['min_range' => 1, 'max_range' => 65535],
    ]);
    $database = filter_var(getenv('REDIS_DATABASE') ?: '0', FILTER_VALIDATE_INT, [
        'options' => ['min_range' => 0, 'max_range' => 15],
    ]);
    if ($port === false || $database === false) {
        throw new RuntimeException('Invalid Redis port or database configuration.');
    }

    $password = (string) (getenv('REDIS_PASSWORD') ?: '');
    if ($password === '' && !in_array(application_environment(), ['local', 'development', 'test'], true)) {
        throw new RuntimeException('REDIS_PASSWORD must be configured in production.');
    }

    return [
        'host' => $host,
        'port' => $port,
        'database' => $database,
        'password' => $password,
        'timeout' => 2.5,
    ];
}

function redis_session_save_path(array $settings): string
{
    $query = [
        'database' => $settings['database'],
        'timeout' => $settings['timeout'],
        'read_timeout' => $settings['timeout'],
    ];
    if ($settings['password'] !== '') {
        $query['auth'] = $settings['password'];
    }

    return sprintf(
        'tcp://%s:%d?%s',
        $settings['host'],
        $settings['port'],
        http_build_query($query, '', '&', PHP_QUERY_RFC3986)
    );
}

function assert_redis_session_store_ready(): void
{
    $settings = redis_session_settings();
    $client = new Redis();

    if (!$client->connect($settings['host'], $settings['port'], $settings['timeout'])) {
        throw new RuntimeException('Unable to connect to the Redis session store.');
    }
    if ($settings['password'] !== '' && !$client->auth($settings['password'])) {
        throw new RuntimeException('Redis session-store authentication failed.');
    }
    if ($settings['database'] !== 0 && !$client->select($settings['database'])) {
        throw new RuntimeException('Unable to select the Redis session database.');
    }

    $pong = $client->ping();
    $client->close();
    if ($pong !== true && strtoupper(ltrim((string) $pong, '+')) !== 'PONG') {
        throw new RuntimeException('Redis session-store health check failed.');
    }
}
