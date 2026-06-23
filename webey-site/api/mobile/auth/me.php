<?php
declare(strict_types=1);

require_once __DIR__ . '/../_bootstrap.php';
require_once __DIR__ . '/../_auth.php';

wb_method('GET');

$auth = mobile_auth($pdo, 'customer');
$user = mobile_user_payload($pdo, 'customer', (int)$auth['user_id']);

wb_ok(['user' => $user]);
