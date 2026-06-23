<?php
/*
 * API genel bootstrap dosyası
 *
 * - Hata ayarları
 * - CORS header'ları
 * - Session
 * - Composer autoload
 * - Firestore bağlantısı ($firestore)
 */

require_once __DIR__ . '/response.php';

// ---------- HATA AYARLARI ----------
ini_set('display_errors', 0);        // Canlıya alınca 0 kalsın
error_reporting(E_ALL);

// ---------- CORS ----------
$origin = $_SERVER['HTTP_ORIGIN'] ?? '*';

// Buraya kendi domainini yazman daha güvenli olur:
// örn: if ($origin === 'https://mybarber.com') { ... }
header('Access-Control-Allow-Origin: ' . $origin);
header('Access-Control-Allow-Credentials: true');
header('Access-Control-Allow-Headers: Content-Type, X-Requested-With');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

// ---------- SESSION ----------
if (session_status() === PHP_SESSION_NONE) {
    session_start();
}

// ---------- COMPOSER AUTOLOAD ----------
$vendorAutoload = __DIR__ . '/../../vendor/autoload.php';
if (!file_exists($vendorAutoload)) {
    jsonResponse(false, 'composer autoload bulunamadı. Lütfen vendor klasörünü yükleyin.', null, 500);
}
require_once $vendorAutoload;

// ---------- FIRESTORE BAĞLANTISI ----------
use Google\Cloud\Firestore\FirestoreClient;

// TODO: BURAYI KENDİ PROJENE GÖRE DÜZENLE
// 1) /public_html/secure/serviceAccount.json dosyasını yükle
// 2) Aşağıdaki projectId ve path değerlerini güncelle

$FIREBASE_PROJECT_ID   = 'YOUR_FIREBASE_PROJECT_ID';
$SERVICE_ACCOUNT_PATH  = __DIR__ . '/../../secure/serviceAccount.json';

if (!file_exists($SERVICE_ACCOUNT_PATH)) {
    jsonResponse(false, 'Service account dosyası bulunamadı: ' . $SERVICE_ACCOUNT_PATH, null, 500);
}

// Google client bu değişkene bakar
putenv('GOOGLE_APPLICATION_CREDENTIALS=' . $SERVICE_ACCOUNT_PATH);

try {
    $firestore = new FirestoreClient([
        'projectId' => $FIREBASE_PROJECT_ID,
    ]);
} catch (Exception $e) {
    jsonResponse(false, 'Firestore bağlantısı kurulamadı: ' . $e->getMessage(), null, 500);
}
