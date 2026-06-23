<?php
declare(strict_types=1);
/**
 * tools/import_turkey_address_dataset.php
 *
 * Türkiye il / ilçe / mahalle dataset import scripti (idempotent).
 *
 * Kullanım:
 *   php tools/import_turkey_address_dataset.php
 *     → 81 ili seeder'dan yükler (bu dosyada gömülü, küçük).
 *
 *   php tools/import_turkey_address_dataset.php --districts=path/to/districts.csv
 *     → CSV: province_id,name (Türkçe karakter destekli UTF-8).
 *
 *   php tools/import_turkey_address_dataset.php --neighborhoods=path/to/neighborhoods.csv
 *     → CSV: province_id,district_name,neighborhood_name (UTF-8).
 *
 * Veri Lisansı / Kaynak (MVP):
 *   - İl listesi: Türkiye Cumhuriyeti İçişleri Bakanlığı / TÜİK kamu verisi (CC0 niteliğinde).
 *   - İlçe / mahalle dataset'i: PTT Posta Kodu dataset'i (kamuya açık).
 *     Tam mahalle dataset'i dahil değil — ayrı CSV ile çalıştırılır.
 *
 * Idempotent davranış:
 *   - INSERT ... ON DUPLICATE KEY UPDATE updated_at = NOW().
 *   - slug benzersizliği üzerinden eşleştirme yapar.
 */

require_once __DIR__ . '/../db.php';

if (PHP_SAPI !== 'cli') {
    fwrite(STDERR, "Bu script yalnızca CLI ile çalıştırılmalıdır.\n");
    exit(1);
}

$opts = getopt('', ['districts:', 'neighborhoods:']);

function wb_slug(string $s): string
{
    $map = ['İ'=>'i','I'=>'i','ı'=>'i','Ş'=>'s','ş'=>'s','Ç'=>'c','ç'=>'c',
            'Ğ'=>'g','ğ'=>'g','Ö'=>'o','ö'=>'o','Ü'=>'u','ü'=>'u'];
    $s = strtr($s, $map);
    $s = mb_strtolower($s, 'UTF-8');
    $s = preg_replace('/[^a-z0-9]+/u', '-', $s) ?? '';
    return trim($s, '-');
}

function out(string $s): void { fwrite(STDOUT, $s . "\n"); }

// ── İl seeder (81 il, plaka kodu) ────────────────────────────────────────────
$provinces = [
    [1,'Adana'],[2,'Adıyaman'],[3,'Afyonkarahisar'],[4,'Ağrı'],[5,'Amasya'],
    [6,'Ankara'],[7,'Antalya'],[8,'Artvin'],[9,'Aydın'],[10,'Balıkesir'],
    [11,'Bilecik'],[12,'Bingöl'],[13,'Bitlis'],[14,'Bolu'],[15,'Burdur'],
    [16,'Bursa'],[17,'Çanakkale'],[18,'Çankırı'],[19,'Çorum'],[20,'Denizli'],
    [21,'Diyarbakır'],[22,'Edirne'],[23,'Elazığ'],[24,'Erzincan'],[25,'Erzurum'],
    [26,'Eskişehir'],[27,'Gaziantep'],[28,'Giresun'],[29,'Gümüşhane'],[30,'Hakkari'],
    [31,'Hatay'],[32,'Isparta'],[33,'Mersin'],[34,'İstanbul'],[35,'İzmir'],
    [36,'Kars'],[37,'Kastamonu'],[38,'Kayseri'],[39,'Kırklareli'],[40,'Kırşehir'],
    [41,'Kocaeli'],[42,'Konya'],[43,'Kütahya'],[44,'Malatya'],[45,'Manisa'],
    [46,'Kahramanmaraş'],[47,'Mardin'],[48,'Muğla'],[49,'Muş'],[50,'Nevşehir'],
    [51,'Niğde'],[52,'Ordu'],[53,'Rize'],[54,'Sakarya'],[55,'Samsun'],
    [56,'Siirt'],[57,'Sinop'],[58,'Sivas'],[59,'Tekirdağ'],[60,'Tokat'],
    [61,'Trabzon'],[62,'Tunceli'],[63,'Şanlıurfa'],[64,'Uşak'],[65,'Van'],
    [66,'Yozgat'],[67,'Zonguldak'],[68,'Aksaray'],[69,'Bayburt'],[70,'Karaman'],
    [71,'Kırıkkale'],[72,'Batman'],[73,'Şırnak'],[74,'Bartın'],[75,'Ardahan'],
    [76,'Iğdır'],[77,'Yalova'],[78,'Karabük'],[79,'Kilis'],[80,'Osmaniye'],
    [81,'Düzce'],
];

$provinceCount = 0;
$pdo->beginTransaction();
try {
    $upsertProv = $pdo->prepare(
        "INSERT INTO address_provinces (id, name, slug, plate_code, created_at, updated_at)
         VALUES (?, ?, ?, ?, NOW(), NOW())
         ON DUPLICATE KEY UPDATE name = VALUES(name), slug = VALUES(slug), updated_at = NOW()"
    );
    foreach ($provinces as [$plate, $name]) {
        $upsertProv->execute([$plate, $name, wb_slug($name), $plate]);
        $provinceCount++;
    }
    $pdo->commit();
} catch (Throwable $e) {
    $pdo->rollBack();
    fwrite(STDERR, "Province import failed: " . $e->getMessage() . "\n");
    exit(2);
}
out("province_count=$provinceCount");

// ── İlçe import (opsiyonel CSV) ──────────────────────────────────────────────
$districtCount = 0;
if (!empty($opts['districts'])) {
    $csv = (string)$opts['districts'];
    if (!is_readable($csv)) {
        fwrite(STDERR, "districts CSV bulunamadı: $csv\n");
        exit(3);
    }
    $h = fopen($csv, 'r');
    if ($h === false) { fwrite(STDERR, "CSV açılamadı\n"); exit(3); }
    $upsertDis = $pdo->prepare(
        "INSERT INTO address_districts (province_id, name, slug, created_at, updated_at)
         VALUES (?, ?, ?, NOW(), NOW())
         ON DUPLICATE KEY UPDATE name = VALUES(name), updated_at = NOW()"
    );
    $pdo->beginTransaction();
    try {
        while (($row = fgetcsv($h)) !== false) {
            if (count($row) < 2) continue;
            $provId = (int)$row[0];
            $name = trim((string)$row[1]);
            if ($provId <= 0 || $name === '') continue;
            $upsertDis->execute([$provId, $name, wb_slug($name)]);
            $districtCount++;
        }
        $pdo->commit();
    } catch (Throwable $e) {
        $pdo->rollBack();
        fclose($h);
        fwrite(STDERR, "District import failed: " . $e->getMessage() . "\n");
        exit(4);
    }
    fclose($h);
}
out("district_count=$districtCount");

// ── Mahalle import (opsiyonel CSV) ───────────────────────────────────────────
$neighborhoodCount = 0;
if (!empty($opts['neighborhoods'])) {
    $csv = (string)$opts['neighborhoods'];
    if (!is_readable($csv)) {
        fwrite(STDERR, "neighborhoods CSV bulunamadı: $csv\n");
        exit(5);
    }
    $h = fopen($csv, 'r');
    if ($h === false) { fwrite(STDERR, "CSV açılamadı\n"); exit(5); }
    // CSV: province_id,district_name,neighborhood_name
    $distLookup = $pdo->prepare(
        'SELECT id FROM address_districts WHERE province_id = ? AND slug = ? LIMIT 1'
    );
    $upsertNeigh = $pdo->prepare(
        "INSERT INTO address_neighborhoods
            (province_id, district_id, name, slug, created_at, updated_at)
         VALUES (?, ?, ?, ?, NOW(), NOW())
         ON DUPLICATE KEY UPDATE name = VALUES(name), updated_at = NOW()"
    );
    $pdo->beginTransaction();
    try {
        $cache = [];
        while (($row = fgetcsv($h)) !== false) {
            if (count($row) < 3) continue;
            $provId = (int)$row[0];
            $distName = trim((string)$row[1]);
            $neighName = trim((string)$row[2]);
            if ($provId <= 0 || $distName === '' || $neighName === '') continue;
            $key = $provId . '|' . $distName;
            if (!isset($cache[$key])) {
                $distLookup->execute([$provId, wb_slug($distName)]);
                $cache[$key] = (int)($distLookup->fetchColumn() ?: 0);
            }
            $distId = $cache[$key];
            if ($distId <= 0) continue;
            $upsertNeigh->execute([$provId, $distId, $neighName, wb_slug($neighName)]);
            $neighborhoodCount++;
        }
        $pdo->commit();
    } catch (Throwable $e) {
        $pdo->rollBack();
        fclose($h);
        fwrite(STDERR, "Neighborhood import failed: " . $e->getMessage() . "\n");
        exit(6);
    }
    fclose($h);
}
out("neighborhood_count=$neighborhoodCount");
out("ok");
