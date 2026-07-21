<?php
declare(strict_types=1);

require_once __DIR__ . '/bootstrap.php';
require_once __DIR__ . '/database.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Allow: POST');
    render_error_page(405, 'Method not allowed', 'Delete requests must be submitted from the member list.');
}

if (!request_csrf_is_valid()) {
    render_error_page(403, 'Request rejected', 'The form expired or was submitted from another site. Please try again.');
}

$id = positive_integer($_POST['id'] ?? null);
if ($id === null) {
    render_error_page(400, 'Invalid member ID', 'Choose a member from the member list and try again.');
}

try {
    $conn = database_connection();
} catch (Throwable $error) {
    error_log('Database connection failed while deleting a member: ' . $error->getMessage());
    render_error_page(503, 'Temporarily unavailable', 'The database service is unavailable. Please try again shortly.');
}

try {
    $statement = $conn->prepare('DELETE FROM users WHERE id = ?');
    $statement->bind_param('i', $id);
    $statement->execute();
    $deletedRows = $statement->affected_rows;
    $statement->close();
    $conn->close();
} catch (Throwable $error) {
    error_log('Unable to delete member: ' . $error->getMessage());
    render_error_page(500, 'Unable to delete member', 'The member could not be deleted. Please try again.');
}

if ($deletedRows === 0) {
    render_error_page(404, 'Member not found', 'The requested member may already have been removed.');
}

redirect_to_index();
