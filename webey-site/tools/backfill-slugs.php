#!/usr/bin/env php
<?php
// tools/backfill-slugs.php
// ─────────────────────────────────────────────────────────────
// Mevcut işletmelere slug oluşturan tek seferlik script.
// CLI'den çalıştır:
//   php tools/backfill-slugs.php
//
// Güvenli: sadece slug'ı BOŞ olan işletmeleri günceller.
// ─────────────────────────────────────────────────────────────
declare(strict_types=1);

if (PHP_SAPI !== 'cli') {
    http_response_code(403);
    exit('Bu script sadece CLI üzerinden çalışır.' . PHP_EOL);
}

require __DIR__ . '/../db.php';
require __DIR__ . '/../api/_slug.php';

echo "Slug backfill başladı...\n";

$stmt = $pdo->query("
    SELECT id, name FROM businesses
    WHERE (slug IS NULL OR slug = '') AND name != ''
    ORDER BY id ASC
");

$rows    = $stmt->fetchAll();
$total   = count($rows);
$updated = 0;
$skipped = 0;

foreach ($rows as $row) {
    $id   = (int)$row['id'];
    $name = $row['name'];

    $slug = wb_generate_slug($pdo, $name, $id);

    if (empty($slug)) {
        echo "  SKIP #{$id} '{$name}' — slug boş oluştu\n";
        $skipped++;
        continue;
    }

    $pdo->prepare("UPDATE businesses SET slug = ? WHERE id = ?")
        ->execute([$slug, $id]);

    echo "  OK #{$id} '{$name}' → '{$slug}'\n";
    $updated++;
}

echo "\nTamamlandı: {$updated}/{$total} güncellendi, {$skipped} atlandı.\n";
echo "Örnek URL: https://webey.com.tr/k/{örnek-slug}\n";