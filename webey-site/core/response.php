<?php
// Basit JSON cevap + yardımcı fonksiyonlar

if (!function_exists('jsonResponse')) {
    function jsonResponse($success, $message = null, $data = null, $statusCode = null)
    {
        if ($statusCode !== null) {
            http_response_code($statusCode);
        }

        $out = ['success' => (bool)$success];

        if ($message !== null) {
            $out['message'] = $message;
        }
        if ($data !== null) {
            $out['data'] = $data;
        }

        header('Content-Type: application/json; charset=utf-8');
        echo json_encode($out, JSON_UNESCAPED_UNICODE);
        exit;
    }
}

if (!function_exists('getJson')) {
    function getJson()
    {
        $raw = file_get_contents('php://input');
        if ($raw === false || $raw === '') {
            return [];
        }

        $data = json_decode($raw, true);
        if (json_last_error() !== JSON_ERROR_NONE) {
            jsonResponse(false, 'Geçersiz JSON: ' . json_last_error_msg(), null, 400);
        }
        return $data;
    }
}

if (!function_exists('requirePost')) {
    function requirePost()
    {
        if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
            jsonResponse(false, 'Sadece POST isteği kabul ediliyor.', null, 405);
        }
    }
}
