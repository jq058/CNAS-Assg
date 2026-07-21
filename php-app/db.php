<?php
declare(strict_types=1);

require_once __DIR__ . '/bootstrap.php';
require_once __DIR__ . '/database.php';

try {
    $conn = database_connection();
} catch (Throwable $error) {
    error_log('Database connection failed: ' . $error->getMessage());
    render_error_page(503, 'Temporarily unavailable', 'The database service is unavailable. Please try again shortly.');
}
