<?php
// api/_sms.php
// ─────────────────────────────────────────────────────────────────────
// Webey SMS Yardımcısı
//
// Kullanım (anlık gönder):
//   require_once __DIR__ . '/_sms.php';
//   wbSms('5321234567', 'Mesaj metni');
//
// Kullanım (kuyruğa ekle — ÖNERİLEN):
//   require_once __DIR__ . '/_sms.php';
//   queueSms($pdo, '5321234567', 'Mesaj metni');
//   queueSms($pdo, '5321234567', 'Mesaj', scheduled: '+1 day'); // ileride gönder
// ─────────────────────────────────────────────────────────────────────
declare(strict_types=1);

// ── SMS Metin Şablonları ─────────────────────────────────────────────

/**
 * Randevu alındı SMS'i (müşteriye)
 */
function smsApptBooked(string $bizName, string $date, string $time): string {
    return "Webey: {$bizName} işletmesine {$date} {$time} için randevunuz iletilmiştir. Onay için bekleyiniz.";
}

/**
 * Randevu onaylandı SMS'i (müşteriye)
 */
function smsApptApproved(string $bizName, string $date, string $time): string {
    return "Webey: {$bizName} randevunuz onaylandı. Tarih: {$date} {$time}. İyi günler dileriz!";
}

/**
 * Randevu reddedildi SMS'i (müşteriye)
 */
function smsApptRejected(string $bizName): string {
    return "Webey: Üzgünüz, {$bizName} randevunuz uygun değil. Yeni randevu için: webey.com.tr";
}

/**
 * 24 saat hatırlatma SMS'i (müşteriye)
 */
function smsReminder24h(string $bizName, string $date, string $time): string {
    return "Webey Hatırlatma: Yarın {$date} {$time} - {$bizName} randevunuz var. Adres için uygulamaya bakın.";
}

/**
 * 1 saat hatırlatma SMS'i (müşteriye)
 */
function smsReminder1h(string $bizName, string $time): string {
    return "Webey Hatırlatma: 1 saat sonra {$time} - {$bizName} randevunuz var. İyi günler!";
}

// ── Kuyruğa Ekle (ÖNERİLEN YÖNTEM) ─────────────────────────────────

/**
 * SMS'i sms_queue tablosuna ekle. cron_send_sms.php işler.
 *
 * @param PDO    $pdo
 * @param string $phone       Alıcı telefon (05XX veya 5XX veya +90...)
 * @param string $message     SMS metni
 * @param string|null $type   Kayıt tipi: 'booking'|'approved'|'rejected'|'reminder_24h'|'reminder_1h'
 * @param int|null $apptId    İlgili appointment id (opsiyonel, izleme için)
 * @param string|null $scheduled  NULL = hemen gönder | '+1 day' | 'Y-m-d H:i:s' formatı
 */
function queueSms(
    PDO $pdo,
    string $phone,
    string $message,
    ?string $type = null,
    ?int $apptId = null,
    ?string $scheduled = null
): bool {
    $phone = _normalizeTrPhone($phone);
    if (!$phone) {
        error_log('[queueSms] Geçersiz telefon: ' . $phone);
        return false;
    }

    // scheduled_at hesapla
    $scheduledAt = null;
    if ($scheduled !== null) {
        try {
            $dt = str_starts_with($scheduled, '+') || str_starts_with($scheduled, '-')
                ? new DateTimeImmutable($scheduled)
                : new DateTimeImmutable($scheduled);
            $scheduledAt = $dt->format('Y-m-d H:i:s');
        } catch (Throwable) {
            $scheduledAt = null;
        }
    }

    try {
        $pdo->prepare("
            INSERT INTO sms_queue
                (phone, message, type, appointment_id, scheduled_at, status, created_at)
            VALUES
                (?, ?, ?, ?, ?, 'pending', NOW())
        ")->execute([$phone, $message, $type, $apptId, $scheduledAt]);
        return true;
    } catch (Throwable $e) {
        error_log('[queueSms] DB hatası: ' . $e->getMessage());
        return false;
    }
}

// ── Anlık Gönder ─────────────────────────────────────────────────────

/**
 * SMS'i anlık gönder (cron kullanmak yerine direkt).
 * Genellikle queueSms() tercih edilmeli.
 *
 * @return bool
 */
function wbSms(string $phone, string $message): bool {
    $phone = _normalizeTrPhone($phone);
    if (!$phone) {
        error_log('[wbSms] Geçersiz telefon: ' . $phone);
        return false;
    }

    $cfg = require __DIR__ . '/_sms_config.php';

    // Debug modunda gerçek SMS gönderme
    if (!empty($cfg['debug'])) {
        error_log('[wbSms DEBUG] To: ' . $phone . ' | Msg: ' . $message);
        return true;
    }

    return match ($cfg['provider']) {
        'netgsm'       => _smsSendNetgsm($cfg['netgsm'], $phone, $message),
        'iletimerkezi' => _smsSendIletimerkezi($cfg['iletimerkezi'], $phone, $message),
        'verimor'      => _smsSendVerimor($cfg['verimor'], $phone, $message),
        default        => (bool)error_log('[wbSms] Bilinmeyen provider: ' . $cfg['provider']),
    };
}

// ── Telefon Normalizer ───────────────────────────────────────────────

/**
 * Türk telefon numarasını 905XXXXXXXXX formatına çevirir.
 * Geçersiz formatlarda false döner.
 */
function _normalizeTrPhone(string $raw): string|false {
    $digits = preg_replace('/\D/', '', $raw);

    // 12 haneli: 905321234567 → zaten doğru
    if (strlen($digits) === 12 && str_starts_with($digits, '90')) {
        return $digits;
    }
    // 11 haneli: 05321234567
    if (strlen($digits) === 11 && str_starts_with($digits, '0')) {
        return '90' . substr($digits, 1);
    }
    // 10 haneli: 5321234567
    if (strlen($digits) === 10 && str_starts_with($digits, '5')) {
        return '90' . $digits;
    }

    return false;
}

// ── Provider Implementasyonları ──────────────────────────────────────

/**
 * Netgsm HTTP API ile gönder
 * Belge: https://www.netgsm.com.tr/dokuman/
 */
function _smsSendNetgsm(array $cfg, string $phone, string $message): bool {
    $params = http_build_query([
        'usercode'  => $cfg['usercode'],
        'password'  => $cfg['password'],
        'gsmno'     => $phone,
        'message'   => $message,
        'msgheader' => $cfg['msgheader'],
        'dil'       => 'TR',
    ]);

    $url = 'https://api.netgsm.com.tr/sms/send/get/?' . $params;

    $ctx = stream_context_create(['http' => ['timeout' => 10]]);
    $resp = @file_get_contents($url, false, $ctx);

    if ($resp === false) {
        error_log('[Netgsm] Bağlantı hatası');
        return false;
    }

    // Netgsm başarılı yanıtı "00 XXXXXXXX" formatındadır
    $code = substr(trim($resp), 0, 2);
    if ($code !== '00') {
        error_log('[Netgsm] Hata kodu: ' . trim($resp));
        return false;
    }
    return true;
}

/**
 * İletimerkezi HTTP API ile gönder
 * Belge: https://www.iletimerkezi.com/belgeler/api
 */
function _smsSendIletimerkezi(array $cfg, string $phone, string $message): bool {
    $body = json_encode([
        'request' => [
            'authentication' => [
                'username' => $cfg['username'],
                'password' => $cfg['password'],
            ],
            'order' => [
                'sender'   => $cfg['sender'],
                'sendtime' => '',
                'message'  => ['text' => $message, 'receipents' => ['number' => [$phone]]],
            ],
        ],
    ]);

    $opts = [
        'http' => [
            'method'  => 'POST',
            'header'  => "Content-Type: application/json\r\nAccept: application/json\r\n",
            'content' => $body,
            'timeout' => 10,
        ],
    ];

    $resp = @file_get_contents('https://api.iletimerkezi.com/v1/send-sms/json', false, stream_context_create($opts));

    if ($resp === false) {
        error_log('[İletimerkezi] Bağlantı hatası');
        return false;
    }

    $json = json_decode($resp, true);
    $code = $json['response']['status']['code'] ?? null;

    if ($code !== 200) {
        error_log('[İletimerkezi] Hata: ' . $resp);
        return false;
    }
    return true;
}

/**
 * Verimor HTTP API ile gönder
 * Belge: https://www.verimor.com.tr/entegrasyon/http-api
 */
function _smsSendVerimor(array $cfg, string $phone, string $message): bool {
    $body = json_encode([
        'username'    => $cfg['username'],
        'password'    => $cfg['password'],
        'source_addr' => $cfg['sender'],
        'messages'    => [['msg' => $message, 'dest' => $phone]],
    ]);

    $opts = [
        'http' => [
            'method'  => 'POST',
            'header'  => "Content-Type: application/json\r\n",
            'content' => $body,
            'timeout' => 10,
        ],
    ];

    $resp = @file_get_contents('https://sms.verimor.com.tr/v2/send.json', false, stream_context_create($opts));

    if ($resp === false) {
        error_log('[Verimor] Bağlantı hatası');
        return false;
    }

    $json = json_decode($resp, true);
    if (!isset($json['campaign_id'])) {
        error_log('[Verimor] Hata: ' . $resp);
        return false;
    }
    return true;
}