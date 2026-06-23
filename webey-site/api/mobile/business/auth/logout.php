<?php
declare(strict_types=1);

require_once __DIR__ . '/../../_bootstrap.php';
require_once __DIR__ . '/../../_auth.php';

wb_method('POST');

mobile_auth($pdo, ['business', 'admin']);
mobile_revoke_current_session($pdo);

wb_ok(['logged_out' => true]);
