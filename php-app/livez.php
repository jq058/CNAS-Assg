<?php
declare(strict_types=1);

http_response_code(200);
header('Content-Type: application/json; charset=UTF-8');
header('Cache-Control: no-store');
echo json_encode(['status' => 'alive'], JSON_THROW_ON_ERROR);
