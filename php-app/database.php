<?php
declare(strict_types=1);

function required_environment_value(string $name): string
{
    $value = getenv($name);
    if ($value === false || trim($value) === '') {
        throw new RuntimeException($name . ' is not configured.');
    }

    return $value;
}

function database_connection(): mysqli
{
    $port = filter_var(getenv('DB_PORT') ?: '3306', FILTER_VALIDATE_INT, [
        'options' => ['min_range' => 1, 'max_range' => 65535],
    ]);
    if ($port === false) {
        throw new RuntimeException('DB_PORT is invalid.');
    }

    mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);
    $connection = mysqli_init();
    if ($connection === false) {
        throw new RuntimeException('Unable to initialize the database client.');
    }

    $connection->options(MYSQLI_OPT_CONNECT_TIMEOUT, 3);
    $connection->real_connect(
        required_environment_value('DB_HOST'),
        required_environment_value('DB_USER'),
        required_environment_value('DB_PASSWORD'),
        required_environment_value('DB_NAME'),
        $port
    );
    $connection->set_charset('utf8mb4');

    return $connection;
}
