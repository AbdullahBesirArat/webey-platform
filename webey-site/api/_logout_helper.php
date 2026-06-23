<?php
declare(strict_types=1);
/**
 * api/_logout_helper.php
 * ───────────────────────────────────────────────────────
 * auth/logout.php ve user/logout.php tarafından paylaşılan
 * logout mantığı. Bu dosyayı doğrudan çağırma — logout
 * endpoint'leri bu dosyayı include eder.
 *
 * Güvenli logout akışı:
 *   1. Session içeriğini temizle
 *   2. Session cookie'yi sil
 *   3. Session'ı yok et
 *   4. Session fixation saldırılarına karşı yeni ID üret
 */

if (session_status() === PHP_SESSION_NONE) {
    ini_set('session.cookie_samesite', 'Lax');
    ini_set('session.cookie_httponly', '1');
    session_start();
}

// 1. Session verisini sıfırla
$_SESSION = [];

// 2. Session cookie'yi geçersiz kıl
if (ini_get('session.use_cookies')) {
    $p = session_get_cookie_params();
    setcookie(
        session_name(), '',
        time() - 42000,
        $p['path'], $p['domain'], $p['secure'], $p['httponly']
    );
}

// 3. Session'ı yok et
session_destroy();

// 4. Yeni boş session başlat + yeni ID üret (fixation önleme)
session_start();
session_regenerate_id(true);

wb_ok(['message' => 'Çıkış yapıldı']);