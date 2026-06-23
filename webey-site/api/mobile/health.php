<?php
declare(strict_types=1);

require_once __DIR__ . '/_bootstrap.php';

wb_method('GET');

wb_ok([
    'status' => 'ok',
    'service' => 'webey-mobile-api',
    'version' => '1.0.0',
    'time' => date(DATE_ATOM),
]);
