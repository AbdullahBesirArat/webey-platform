<?php
// api/profile/logout.php — Geriye Dönük Uyumluluk Shim
// YENİ KOD: /api/auth/logout.php veya /api/user/logout.php kullan.
declare(strict_types=1);
require_once __DIR__ . '/../_public_bootstrap.php';
wb_method('POST');
require __DIR__ . '/../_logout_helper.php';