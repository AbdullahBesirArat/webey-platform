<?php
declare(strict_types=1);
/**
 * api/billing/_plans.php — Merkezi Plan Tanımları
 * ══════════════════════════════════════════════════
 * subscribe.php ve apply-promo.php bu dosyayı require eder.
 * Fiyat veya plan adı değiştiğinde SADECE bu dosyayı güncelle.
 *
 * Kullanım:
 *   require_once __DIR__ . '/_plans.php';
 *   $plan = WB_PLANS['monthly_1']; // ['months'=>1, 'price'=>1150, 'label'=>'1 Aylık Plan']
 */

if (!defined('WB_PLANS')) {
    define('WB_PLANS', [
        'monthly_1' => ['months' => 1,  'price' => 1150,  'label' => '1 Aylık Plan'],
        'monthly_3' => ['months' => 3,  'price' => 2865,  'label' => '3 Aylık Plan'],
        'monthly_6' => ['months' => 6,  'price' => 4620,  'label' => '6 Aylık Plan'],
        'yearly_1'  => ['months' => 12, 'price' => 6900,  'label' => '1 Yıllık Plan'],
        'yearly_2'  => ['months' => 24, 'price' => 11040, 'label' => '2 Yıllık Plan'],
    ]);
}