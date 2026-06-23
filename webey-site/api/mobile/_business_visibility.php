<?php
declare(strict_types=1);

/**
 * Customer-visible business subscription/boost resolver.
 *
 * Uses only the new business_id based subscription tables. Legacy web/iyzico
 * subscriptions are intentionally ignored.
 */

if (!function_exists('wb_business_visibility_table_exists')) {
    function wb_business_visibility_table_exists(PDO $pdo, string $table): bool
    {
        static $cache = [];
        $allowed = [
            'business_subscriptions',
            'business_boost_subscriptions',
            'boost_packages',
            'business_photos',
            'services',
            'business_hours',
        ];
        if (!in_array($table, $allowed, true)) {
            return false;
        }
        if (!array_key_exists($table, $cache)) {
            try {
                $stmt = $pdo->prepare(
                    "SELECT COUNT(*) FROM information_schema.tables
                     WHERE table_schema = DATABASE() AND table_name = ?"
                );
                $stmt->execute([$table]);
                $cache[$table] = (int)$stmt->fetchColumn() > 0;
            } catch (Throwable $e) {
                error_log('[wb_business_visibility_table_exists] ' . $table . ': ' . $e->getMessage());
                $cache[$table] = false;
            }
        }
        return $cache[$table];
    }

    function wb_business_visibility_has_subscriptions(PDO $pdo): bool
    {
        return wb_business_visibility_table_exists($pdo, 'business_subscriptions');
    }

    function wb_business_visibility_has_boost(PDO $pdo): bool
    {
        return wb_business_visibility_table_exists($pdo, 'business_boost_subscriptions')
            && wb_business_visibility_table_exists($pdo, 'boost_packages');
    }

    function wb_business_visibility_join_sql(PDO $pdo): string
    {
        $sql = '';
        if (wb_business_visibility_has_subscriptions($pdo)) {
            $sql .= "
                LEFT JOIN business_subscriptions bs
                  ON bs.id = (
                    SELECT bs2.id
                    FROM business_subscriptions bs2
                    WHERE bs2.business_id = b.id
                    ORDER BY bs2.id DESC
                    LIMIT 1
                  )";
        }
        if (wb_business_visibility_has_boost($pdo)) {
            $sql .= "
                LEFT JOIN business_boost_subscriptions bboost
                  ON bboost.id = (
                    SELECT bbs2.id
                    FROM business_boost_subscriptions bbs2
                    WHERE bbs2.business_id = b.id
                      AND bbs2.status = 'active'
                      AND (bbs2.ends_at IS NULL OR bbs2.ends_at >= NOW())
                    ORDER BY bbs2.ends_at DESC, bbs2.id DESC
                    LIMIT 1
                  )
                LEFT JOIN boost_packages boostp ON boostp.id = bboost.package_id";
        }
        return $sql;
    }

    function wb_business_visibility_select_sql(PDO $pdo): string
    {
        $subSelect = wb_business_visibility_has_subscriptions($pdo)
            ? ",
               COALESCE(bs.status, 'missing') AS subscription_status,
               CASE
                 WHEN bs.id IS NULL THEN 'temporary_visible'
                 WHEN bs.status IN ('trial','active','overdue') THEN 'visible'
                 WHEN bs.status IN ('suspended','cancelled') THEN 'hidden'
                 ELSE 'temporary_visible'
               END AS visibility_status"
            : ",
               'unknown' AS subscription_status,
               'temporary_visible' AS visibility_status";

        $boostSelect = wb_business_visibility_has_boost($pdo)
            ? ",
               (bboost.id IS NOT NULL) AS is_boosted,
               CASE WHEN bboost.id IS NOT NULL THEN COALESCE(boostp.name, 'Öne Çıkan') ELSE NULL END AS boost_badge,
               bboost.ends_at AS boost_ends_at,
               COALESCE(boostp.priority_weight, 0) AS boost_priority"
            : ",
               0 AS is_boosted,
               NULL AS boost_badge,
               NULL AS boost_ends_at,
               0 AS boost_priority";

        $coverScore = wb_business_visibility_table_exists($pdo, 'business_photos')
            ? "CASE WHEN EXISTS (
                   SELECT 1 FROM business_photos qp
                   WHERE qp.business_id = b.id AND qp.status = 'active' AND qp.is_visible = 1 AND qp.is_cover = 1
                 ) THEN 30 ELSE 0 END"
            : '0';
        $serviceScore = wb_business_visibility_table_exists($pdo, 'services')
            ? "LEAST(3, (SELECT COUNT(*) FROM services qs WHERE qs.business_id = b.id)) * 15"
            : '0';
        $hoursScore = wb_business_visibility_table_exists($pdo, 'business_hours')
            ? "CASE WHEN EXISTS (
                   SELECT 1 FROM business_hours qh
                   WHERE qh.business_id = b.id AND qh.is_open = 1
                 ) THEN 15 ELSE 0 END"
            : '0';
        $locationScore = "CASE WHEN b.latitude IS NOT NULL AND b.longitude IS NOT NULL
                   AND NOT (ABS(b.latitude) < 0.0001 AND ABS(b.longitude) < 0.0001)
                   THEN 10 ELSE 0 END";
        $qualitySelect = ",
               (
                 {$coverScore}
                 + {$serviceScore}
                 + {$hoursScore}
                 + {$locationScore}
               ) AS profile_quality_score";

        return $subSelect . $boostSelect . $qualitySelect;
    }

    function wb_business_visibility_where_sql(PDO $pdo): string
    {
        if (!wb_business_visibility_has_subscriptions($pdo)) {
            return '';
        }
        return " AND (bs.id IS NULL OR bs.status IN ('trial','active','overdue'))";
    }

    function wb_business_visibility_order_prefix_sql(PDO $pdo): string
    {
        $boost = wb_business_visibility_has_boost($pdo)
            ? 'is_boosted DESC, boost_priority DESC, boost_ends_at DESC, '
            : '';
        $sub = wb_business_visibility_has_subscriptions($pdo)
            ? "CASE
                 WHEN subscription_status IN ('trial','active') THEN 0
                 WHEN subscription_status = 'overdue' THEN 1
                 WHEN subscription_status = 'missing' THEN 2
                 ELSE 3
               END ASC, "
            : '';
        return $boost . $sub . 'profile_quality_score DESC, ';
    }

    function wb_business_visibility_from_row(array $row): array
    {
        $subscriptionStatus = (string)($row['subscription_status'] ?? 'unknown');
        $visibilityStatus = (string)($row['visibility_status'] ?? 'temporary_visible');
        $isBoosted = (bool)($row['is_boosted'] ?? false);
        return [
            'subscription_status' => $subscriptionStatus,
            'visibility_status' => $visibilityStatus,
            'is_boosted' => $isBoosted,
            'boost_badge' => $isBoosted ? ($row['boost_badge'] ?? 'Öne Çıkan') : null,
            'boost_ends_at' => $isBoosted ? ($row['boost_ends_at'] ?? null) : null,
            'profile_quality_score' => (int)($row['profile_quality_score'] ?? 0),
        ];
    }
}
