<?php
declare(strict_types=1);

require_once __DIR__ . '/database.php';
require_once __DIR__ . '/session_store.php';

header('Content-Type: application/json; charset=UTF-8');
header('Cache-Control: no-store');

try {
    $connection = database_connection();
    $connection->query('SELECT 1');
    $connection->close();
    if (configured_session_handler() === 'redis') {
        assert_redis_session_store_ready();
    }
    http_response_code(200);
    echo json_encode(['status' => 'ready'], JSON_THROW_ON_ERROR);
} catch (Throwable $error) {
    error_log('Readiness check failed: ' . $error->getMessage());
    http_response_code(503);
    echo json_encode(['status' => 'not ready'], JSON_THROW_ON_ERROR);
}
