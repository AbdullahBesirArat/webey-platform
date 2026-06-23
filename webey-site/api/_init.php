<?php
declare(strict_types=1);

ini_set('display_errors', '0');
ini_set('display_startup_errors', '0');
error_reporting(E_ALL);

require_once __DIR__ . '/wb_response.php';
require_once __DIR__ . '/../db.php';
require_once __DIR__ . '/_helpers.php';

// ── CSRF Koruması (Public Endpoint'ler) ──
// strict=false: Eğer session token henüz oluşmamışsa geçişe izin ver.
// Frontend csrf.php'yi çağırdıktan sonra strict koruma devreye girer.
wb_csrf_verify(false);