<?php
declare(strict_types=1);
/**
 * api/billing/plans.php
 * GET - Merkezi plan kataloğunu döndürür.
 */

require_once __DIR__ . '/../_public_bootstrap.php';
require_once __DIR__ . '/_plans.php';

wb_method('GET');

$baseMonthlyPrice = (float)(WB_PLANS['monthly_1']['price'] ?? 0);
$plans = [];

foreach (WB_PLANS as $key => $plan) {
    $months = (int)($plan['months'] ?? 0);
    $price = (float)($plan['price'] ?? 0);
    $displayLabel = preg_replace('/\s+Plan$/u', '', (string)($plan['label'] ?? $key)) ?: $key;
    $monthlyPrice = $months > 0 ? round($price / $months, 2) : $price;
    $discountPercent = ($baseMonthlyPrice > 0 && $months > 0)
        ? max(0, (int)round((1 - ($monthlyPrice / $baseMonthlyPrice)) * 100))
        : 0;
    $badgeLabel = str_starts_with($key, 'yearly_')
        ? (string)max(1, (int)round($months / 12)) . 'Y'
        : (string)$months . 'A';

    $plans[$key] = [
        'key'              => $key,
        'label'            => (string)($plan['label'] ?? $key),
        'display_label'    => $displayLabel,
        'badge_label'      => $badgeLabel,
        'months'           => $months,
        'price'            => $price,
        'monthly_price'    => $monthlyPrice,
        'discount_percent' => $discountPercent,
    ];
}

wb_ok([
    'plans'              => $plans,
    'order'              => array_keys(WB_PLANS),
    'base_monthly_price' => $baseMonthlyPrice,
]);
