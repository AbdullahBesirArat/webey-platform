<?php
declare(strict_types=1);
/**
 * api/user/logout.php — Müşteri (end-user) çıkışı
 */
require_once __DIR__ . '/../_public_bootstrap.php';

wb_method('POST');

require __DIR__ . '/../_logout_helper.php';