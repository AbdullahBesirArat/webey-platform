<?php
declare(strict_types=1);

/**
 * Kapora IBAN ayarları için ortak yardımcılar.
 * MVP: para Webey'de toplanmaz; müşteri kaporayı doğrudan salonun IBAN'ına yollar.
 */

/** IBAN'ı normalize eder: boşlukları siler, büyük harfe çevirir. */
function wb_normalize_iban(string $raw): string
{
    return strtoupper(preg_replace('/\s+/', '', $raw) ?? '');
}

/** TR IBAN format kontrolü: TR + 24 hane = 26 karakter. */
function wb_is_valid_tr_iban(string $iban): bool
{
    $iban = wb_normalize_iban($iban);
    return (bool)preg_match('/^TR[0-9]{24}$/', $iban);
}

/** IBAN'ı okunabilir formatta gösterir: 4'lü gruplar. */
function wb_format_iban(string $iban): string
{
    $iban = wb_normalize_iban($iban);
    if ($iban === '') {
        return '';
    }
    return trim(chunk_split($iban, 4, ' '));
}

/**
 * Bir işletmenin kapora ödeme ayarlarını döner (yoksa varsayılan kapalı).
 *
 * @return array{deposit_enabled:bool,iban:string,iban_formatted:string,account_holder:?string,bank_name:?string,instructions:?string,has_iban:bool}
 */
function wb_business_payment_settings(PDO $pdo, int $businessId): array
{
    $default = [
        'deposit_enabled' => false,
        'iban' => '',
        'iban_formatted' => '',
        'account_holder' => null,
        'bank_name' => null,
        'instructions' => null,
        'has_iban' => false,
    ];

    if (!mobile_table_has_column($pdo, 'business_payment_settings', 'id')) {
        return $default;
    }

    try {
        $stmt = $pdo->prepare(
            'SELECT deposit_enabled, iban, account_holder, bank_name, instructions
               FROM business_payment_settings
              WHERE business_id = ?
              LIMIT 1'
        );
        $stmt->execute([$businessId]);
        $row = $stmt->fetch();
    } catch (Throwable $e) {
        error_log('[wb_business_payment_settings] ' . $e->getMessage());
        return $default;
    }

    if (!$row) {
        return $default;
    }

    $iban = (string)($row['iban'] ?? '');
    return [
        'deposit_enabled' => (bool)($row['deposit_enabled'] ?? false),
        'iban' => $iban,
        'iban_formatted' => wb_format_iban($iban),
        'account_holder' => ($row['account_holder'] ?? '') !== '' ? (string)$row['account_holder'] : null,
        'bank_name' => ($row['bank_name'] ?? '') !== '' ? (string)$row['bank_name'] : null,
        'instructions' => ($row['instructions'] ?? '') !== '' ? (string)$row['instructions'] : null,
        'has_iban' => $iban !== '',
    ];
}

/** Randevuya özel kapora açıklama kodu üretir (legacy fallback). */
function wb_deposit_reference_code(int $appointmentId): string
{
    return 'WEBEY-APT-' . $appointmentId;
}

/**
 * İşletme adından açıklama kodu slug'ı: Türkçe karakter sadeleştirme,
 * ilk kelime, max 8 karakter, yalnızca A-Z0-9. Boş kalırsa 'SALON'.
 */
function wb_deposit_slug_from_name(string $name): string
{
    $map = [
        'Ğ' => 'G', 'ğ' => 'G', 'Ü' => 'U', 'ü' => 'U', 'Ş' => 'S', 'ş' => 'S',
        'İ' => 'I', 'ı' => 'I', 'i' => 'I', 'Ö' => 'O', 'ö' => 'O', 'Ç' => 'C', 'ç' => 'C',
    ];
    $parts = preg_split('/\s+/u', trim($name)) ?: [];
    $first = (string)($parts[0] ?? '');
    $first = strtr($first, $map);
    $first = strtoupper($first);
    $first = (string)preg_replace('/[^A-Z0-9]/', '', $first);
    $first = substr($first, 0, 8);
    return $first !== '' ? $first : 'SALON';
}

/** Açıklama kodu format kontrolü: WEBEY-{SLUG}-{SAYI}. */
function wb_deposit_reference_is_valid(string $code): bool
{
    return (bool)preg_match('/^WEBEY-[A-Z0-9]{1,8}-[0-9]{4,8}$/', $code);
}

/**
 * Benzersiz kapora açıklama kodu üretir: WEBEY-{ISLETME}-{RASTGELE}.
 * İstemciden gelen aday kod geçerli ve boşta ise aynen kullanılır (müşteri
 * confirm ekranında gördüğü kodla birebir aynı kod kaydedilsin diye);
 * değilse backend yeni kod üretir. Çakışma kalırsa appointment id'ye düşer.
 */
function wb_generate_unique_deposit_reference(
    PDO $pdo,
    string $businessName,
    ?string $candidate = null,
    int $appointmentId = 0
): string {
    $hasCol = mobile_table_has_column($pdo, 'appointments', 'deposit_reference_code');
    $isFree = static function (string $code) use ($pdo, $hasCol, $appointmentId): bool {
        if (!$hasCol) {
            return true;
        }
        try {
            $stmt = $pdo->prepare(
                'SELECT id FROM appointments WHERE deposit_reference_code = ? AND id <> ? LIMIT 1'
            );
            $stmt->execute([$code, $appointmentId]);
            return $stmt->fetch() === false;
        } catch (Throwable $e) {
            error_log('[wb_generate_unique_deposit_reference] ' . $e->getMessage());
            return true;
        }
    };

    $candidate = strtoupper(trim((string)$candidate));
    if ($candidate !== '' && wb_deposit_reference_is_valid($candidate) && $isFree($candidate)) {
        return $candidate;
    }

    $slug = wb_deposit_slug_from_name($businessName);
    for ($i = 0; $i < 6; $i++) {
        $code = 'WEBEY-' . $slug . '-' . random_int(100000, 999999);
        if ($isFree($code)) {
            return $code;
        }
    }
    // Son çare: appointment id garanti benzersizdir.
    return 'WEBEY-' . $slug . '-' . ($appointmentId > 0
        ? (string)$appointmentId
        : (string)random_int(10000000, 99999999));
}
