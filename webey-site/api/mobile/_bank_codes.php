<?php
declare(strict_types=1);
/**
 * api/mobile/_bank_codes.php
 * TR IBAN banka kodu → banka adı eşlemesi.
 *
 * Türkiye IBAN formatı: TR + 2 kontrol + 5 banka kodu + 17 hane = 26 karakter.
 * Banka adı IBAN'dan tahmin edilebilir, kart tipi (Visa/Mastercard/Troy) edilemez.
 */

if (!function_exists('wb_bank_code_from_iban')) {
    function wb_bank_code_from_iban(string $iban): ?string
    {
        $iban = strtoupper(preg_replace('/\s+/', '', $iban) ?? '');
        if (!preg_match('/^TR[0-9]{24}$/', $iban)) {
            return null;
        }
        return substr($iban, 4, 5);
    }

    function wb_bank_name_from_iban(string $iban): ?string
    {
        $code = wb_bank_code_from_iban($iban);
        if ($code === null) {
            return null;
        }
        $map = wb_tr_bank_map();
        return $map[$code] ?? null;
    }

    function wb_tr_bank_map(): array
    {
        return [
            '00010' => 'Ziraat Bankası',
            '00012' => 'Halkbank',
            '00015' => 'VakıfBank',
            '00046' => 'Akbank',
            '00059' => 'Şekerbank',
            '00062' => 'Garanti BBVA',
            '00064' => 'Türkiye İş Bankası',
            '00067' => 'Yapı Kredi',
            '00099' => 'ING Bank',
            '00103' => 'Fibabanka',
            '00109' => 'ICBC Turkey Bank',
            '00111' => 'QNB Finansbank',
            '00123' => 'HSBC Bank',
            '00124' => 'Alternatif Bank',
            '00125' => 'Burgan Bank',
            '00134' => 'DenizBank',
            '00135' => 'Anadolubank',
            '00143' => 'Aktif Bank',
            '00146' => 'Odea Bank',
            '00203' => 'Albaraka Türk',
            '00205' => 'Kuveyt Türk',
            '00206' => 'Türkiye Finans',
            '00209' => 'Ziraat Katılım',
            '00210' => 'Vakıf Katılım',
            '00211' => 'Emlak Katılım',
            '00212' => 'Hayat Finans Katılım',
        ];
    }
}
