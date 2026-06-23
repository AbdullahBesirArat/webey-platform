<?php
declare(strict_types=1);

/**
 * api/superadmin/app/_helpers.php
 * ══════════════════════════════════════════════════════════════
 * App Verileri paneli ortak helper'ları.
 * FAZ 1 READ-ONLY: Bu klasördeki hiçbir endpoint INSERT/UPDATE/DELETE yapmaz.
 *
 * Maskeleme kuralı: password_hash, reset_token, email_verify_token,
 * google_id, token, token_hash, device_id, raw_payload, checkout_token,
 * provider_payment_id alanları SELECT bile edilmez.
 * ══════════════════════════════════════════════════════════════
 */

if (!function_exists('sa_mask_phone')) {

    /** 05321234567 → 0532 *** 45 67 ; kısa/boş değerlerde güvenli davranır. */
    function sa_mask_phone(?string $phone): ?string
    {
        if ($phone === null) return null;
        $digits = preg_replace('/\D+/', '', $phone);
        if ($digits === '' ) return null;
        if (strlen($digits) < 7) return str_repeat('*', strlen($digits));
        $head = substr($digits, 0, 4);
        $tail = substr($digits, -4);
        return $head . ' *** ' . substr($tail, 0, 2) . ' ' . substr($tail, 2);
    }

    /** ali@example.com → a***@e***.com */
    function sa_mask_email(?string $email): ?string
    {
        if ($email === null || strpos($email, '@') === false) return null;
        [$local, $domain] = explode('@', $email, 2);
        $dotPos  = strrpos($domain, '.');
        $domBase = $dotPos !== false ? substr($domain, 0, $dotPos) : $domain;
        $domExt  = $dotPos !== false ? substr($domain, $dotPos) : '';
        $maskPart = static function (string $s): string {
            if ($s === '') return '';
            return mb_substr($s, 0, 1) . '***';
        };
        return $maskPart($local) . '@' . $maskPart($domBase) . $domExt;
    }

    /** TR12 3456 ... → TR** **** 1234 (sadece son 4 hane). */
    function sa_mask_iban(?string $iban): ?string
    {
        if ($iban === null) return null;
        $clean = preg_replace('/\s+/', '', $iban);
        if ($clean === '' || strlen($clean) < 8) return null;
        return substr($clean, 0, 2) . '** **** ' . substr($clean, -4);
    }

    /**
     * GET'ten page/limit okur. limit 1..100 aralığına sıkıştırılır.
     * @return array{page:int, limit:int, offset:int}
     */
    function sa_page_params(int $defaultLimit = 25): array
    {
        $page  = max(1, (int)($_GET['page'] ?? 1));
        $limit = (int)($_GET['limit'] ?? $defaultLimit);
        $limit = max(1, min(100, $limit));
        return ['page' => $page, 'limit' => $limit, 'offset' => ($page - 1) * $limit];
    }

    /** LIKE araması için kullanıcı girdisini escape eder. */
    function sa_like(string $q): string
    {
        return '%' . str_replace(['\\', '%', '_'], ['\\\\', '\\%', '\\_'], trim($q)) . '%';
    }

    /**
     * Prepared statement çalıştırır ve tüm satırları döner.
     * @param array<int|string, mixed> $params
     * @return array<int, array<string, mixed>>
     */
    function sa_rows(PDO $pdo, string $sql, array $params = []): array
    {
        $st = $pdo->prepare($sql);
        $st->execute($params);
        return $st->fetchAll(PDO::FETCH_ASSOC);
    }

    /** Tek satır döner (yoksa null). */
    function sa_row(PDO $pdo, string $sql, array $params = []): ?array
    {
        $st = $pdo->prepare($sql);
        $st->execute($params);
        $row = $st->fetch(PDO::FETCH_ASSOC);
        return $row === false ? null : $row;
    }

    /** Tek skaler değer döner (COUNT vb.). */
    function sa_val(PDO $pdo, string $sql, array $params = []): mixed
    {
        $st = $pdo->prepare($sql);
        $st->execute($params);
        return $st->fetchColumn();
    }

    /** Liste yanıtlarını standart pagination zarfına koyar. */
    function sa_list_payload(array $items, int $total, array $pg): array
    {
        return [
            'items' => $items,
            'pagination' => [
                'page'  => $pg['page'],
                'limit' => $pg['limit'],
                'total' => $total,
                'pages' => (int)ceil($total / max(1, $pg['limit'])),
            ],
        ];
    }
}
