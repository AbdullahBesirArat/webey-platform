<?php
declare(strict_types=1);

require_once __DIR__ . '/../../_bootstrap.php';
require_once __DIR__ . '/../../_auth.php';

wb_method('GET');

$auth = mobile_auth($pdo, ['business', 'admin']);
$user = mobile_user_payload($pdo, (string)$auth['user_type'], (int)$auth['user_id']);

wb_ok(['user' => $user]);
