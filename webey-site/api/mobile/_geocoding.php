<?php
declare(strict_types=1);
/**
 * api/mobile/_geocoding.php
 * Best-effort address → (lat,lng) çevirici.
 *
 * Strateji:
 *   1. WB_GEOCODING_DISABLED=1 ise hiçbir şey yapma; null döner.
 *   2. WB_GOOGLE_MAPS_API_KEY varsa Google Geocoding API (cited, official).
 *   3. Yoksa Nominatim (OSM) — düşük volume, User-Agent zorunlu.
 *   4. Hata olursa null döner; çağıran taraf akışı bozmamalı.
 *
 * Güvenlik:
 *   - API key loglanmaz.
 *   - Kişisel adres URL'i loglanmadan önce kırpılır.
 */

if (!function_exists('wb_geocode_address')) {
    /**
     * @return array{lat:float,lng:float,source:string,confidence:string}|null
     */
    function wb_geocode_address(string $fullAddress): ?array
    {
        $fullAddress = trim($fullAddress);
        if ($fullAddress === '' || mb_strlen($fullAddress) < 6) {
            return null;
        }
        $disabled = getenv('WB_GEOCODING_DISABLED');
        if ($disabled !== false && $disabled !== '' && $disabled !== '0') {
            return null;
        }

        $googleKey = (string)(getenv('WB_GOOGLE_MAPS_API_KEY') ?: '');
        if ($googleKey !== '') {
            $r = _wb_geocode_google($fullAddress, $googleKey);
            if ($r !== null) return $r;
        }

        return _wb_geocode_nominatim($fullAddress);
    }
}

if (!function_exists('_wb_geocode_google')) {
    function _wb_geocode_google(string $address, string $key): ?array
    {
        $url = 'https://maps.googleapis.com/maps/api/geocode/json?address='
            . urlencode($address) . '&region=tr&language=tr&key=' . urlencode($key);
        $raw = _wb_geocode_http($url, 'Webey/1.0');
        if ($raw === null) return null;
        $data = json_decode($raw, true);
        if (!is_array($data) || ($data['status'] ?? '') !== 'OK' || empty($data['results'])) {
            return null;
        }
        $first = $data['results'][0];
        $loc = $first['geometry']['location'] ?? null;
        if (!is_array($loc) || !isset($loc['lat'], $loc['lng'])) {
            return null;
        }
        $type = (string)($first['geometry']['location_type'] ?? '');
        $confidence = match ($type) {
            'ROOFTOP' => 'exact',
            'RANGE_INTERPOLATED', 'GEOMETRIC_CENTER' => 'approx',
            default => 'approx',
        };
        return [
            'lat' => (float)$loc['lat'],
            'lng' => (float)$loc['lng'],
            'source' => 'google',
            'confidence' => $confidence,
        ];
    }
}

if (!function_exists('_wb_geocode_nominatim')) {
    function _wb_geocode_nominatim(string $address): ?array
    {
        $url = 'https://nominatim.openstreetmap.org/search?format=json&limit=1&accept-language=tr&countrycodes=tr&q='
            . urlencode($address);
        // Nominatim için anlamlı UA zorunlu (Usage Policy).
        $raw = _wb_geocode_http($url, 'Webey/1.0 (https://webey.com.tr; contact: destek@webey.com.tr)');
        if ($raw === null) return null;
        $data = json_decode($raw, true);
        if (!is_array($data) || empty($data)) return null;
        $first = $data[0] ?? null;
        if (!is_array($first) || !isset($first['lat'], $first['lon'])) return null;
        return [
            'lat' => (float)$first['lat'],
            'lng' => (float)$first['lon'],
            'source' => 'osm',
            'confidence' => 'approx',
        ];
    }
}

if (!function_exists('_wb_geocode_http')) {
    function _wb_geocode_http(string $url, string $userAgent): ?string
    {
        if (!function_exists('curl_init')) {
            return null;
        }
        $ch = curl_init($url);
        if ($ch === false) return null;
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_FOLLOWLOCATION => true,
            CURLOPT_CONNECTTIMEOUT => 4,
            CURLOPT_TIMEOUT => 6,
            CURLOPT_USERAGENT => $userAgent,
            CURLOPT_HTTPHEADER => ['Accept: application/json'],
        ]);
        $body = curl_exec($ch);
        $http = (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
        $err = curl_error($ch);
        curl_close($ch);
        if ($body === false || $http < 200 || $http >= 300) {
            // Sadece host + status logla; tam URL personal address içerebilir.
            $host = parse_url($url, PHP_URL_HOST) ?: '?';
            error_log("[geocode] host=$host status=$http err=$err");
            return null;
        }
        return is_string($body) ? $body : null;
    }
}

/**
 * Adres alanlarını okunabilir tek bir string'e dönüştürür.
 */
if (!function_exists('wb_build_full_address')) {
    function wb_build_full_address(array $parts): string
    {
        $street = trim((string)($parts['street_name'] ?? ''));
        $building = trim((string)($parts['building_no'] ?? ''));
        $neighborhood = trim((string)($parts['neighborhood'] ?? ''));
        $district = trim((string)($parts['district'] ?? ''));
        $city = trim((string)($parts['city'] ?? ''));

        $segments = [];
        if ($street !== '') {
            $segments[] = $building !== '' ? "$street No:$building" : $street;
        }
        if ($neighborhood !== '') $segments[] = $neighborhood;
        if ($district !== '') $segments[] = $district;
        if ($city !== '') $segments[] = $city;
        $segments[] = 'Türkiye';
        return implode(', ', $segments);
    }
}
