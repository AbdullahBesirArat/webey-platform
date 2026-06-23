<?php
// api/_mailer.php
// Webey email sending: Brevo API + SMTP fallback
declare(strict_types=1);

function wbMailSetLastError(string $code, string $provider = '', string $message = ''): void
{
    $GLOBALS['__WB_MAIL_LAST_ERROR'] = [
        'code' => $code,
        'provider' => $provider,
        'message' => $message,
    ];
}

function wbMailGetLastError(): array
{
    $e = $GLOBALS['__WB_MAIL_LAST_ERROR'] ?? null;
    return is_array($e) ? $e : ['code' => 'unknown', 'provider' => '', 'message' => ''];
}

function wbMail(
    string $toEmail,
    string $toName,
    string $subject,
    string $htmlBody,
    string $textBody = ''
): bool {
    wbMailSetLastError('unknown', '', '');

    if (empty($toEmail) || !filter_var($toEmail, FILTER_VALIDATE_EMAIL)) {
        error_log('[wbMail] Invalid email: ' . $toEmail);
        wbMailSetLastError('invalid_email', 'input', 'Invalid recipient email');
        return false;
    }

    $cfg = require __DIR__ . '/_email_config.php';

    if (!empty($cfg['debug'])) {
        error_log('[wbMail DEBUG] To: ' . $toEmail . ' | Subject: ' . $subject);
        wbMailSetLastError('ok', 'debug', '');
        return true;
    }

    if (!$textBody) {
        $textBody = html_entity_decode(
            strip_tags(str_replace(['<br>', '<br/>', '<br />', '</p>', '</div>'], "\n", $htmlBody)),
            ENT_QUOTES,
            'UTF-8'
        );
        $textBody = preg_replace('/\n{3,}/', "\n\n", trim($textBody));
    }

    if (!empty($cfg['brevo_api_key'])) {
        $ok = _wbMailBrevoApi($cfg, $toEmail, $toName, $subject, $htmlBody, $textBody);
        if ($ok) wbMailSetLastError('ok', 'brevo_api', '');
        return $ok;
    }

    $vendorAutoload = __DIR__ . '/../../vendor/autoload.php';
    if (file_exists($vendorAutoload)) {
        $ok = _wbMailPHPMailer($cfg, $toEmail, $toName, $subject, $htmlBody, $textBody);
        if ($ok) wbMailSetLastError('ok', 'phpmailer', '');
        return $ok;
    }

    $ok = _wbMailSmtp($cfg, $toEmail, $toName, $subject, $htmlBody, $textBody);
    if ($ok) wbMailSetLastError('ok', 'smtp', '');
    return $ok;
}

function _wbMailBrevoApi(array $cfg, string $to, string $toName, string $subject, string $html, string $text): bool
{
    $payload = json_encode([
        'sender' => ['name' => $cfg['from_name'], 'email' => $cfg['from_email']],
        'to' => [['email' => $to, 'name' => $toName ?: $to]],
        'subject' => $subject,
        'htmlContent' => $html,
        'textContent' => $text,
    ]);

    $apiKey = (string)$cfg['brevo_api_key'];
    $code = 0;
    $resp = '';

    if (function_exists('curl_init')) {
        $ch = curl_init();
        curl_setopt_array($ch, [
            CURLOPT_URL => 'https://api.brevo.com/v3/smtp/email',
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_POST => true,
            CURLOPT_POSTFIELDS => $payload,
            CURLOPT_HTTPHEADER => [
                'Content-Type: application/json',
                'Accept: application/json',
                'api-key: ' . $apiKey,
            ],
            CURLOPT_TIMEOUT => 15,
        ]);
        $resp = (string)curl_exec($ch);
        $code = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
        if (curl_error($ch)) {
            $err = curl_error($ch);
            error_log('[wbMail BrevoAPI] cURL error: ' . $err);
            wbMailSetLastError('brevo_network_error', 'brevo_api', $err);
        }
        curl_close($ch);
    } else {
        $opts = ['http' => [
            'method' => 'POST',
            'timeout' => 15,
            'header' => "Content-Type: application/json\r\nAccept: application/json\r\napi-key: {$apiKey}",
            'content' => (string)$payload,
            'ignore_errors' => true,
        ]];
        $resp = (string)@file_get_contents('https://api.brevo.com/v3/smtp/email', false, stream_context_create($opts));
        preg_match('/HTTP\/\S+\s+(\d+)/', ($http_response_header[0] ?? ''), $m);
        $code = (int)($m[1] ?? 0);
    }

    if ($code === 201) {
        error_log('[wbMail BrevoAPI] OK -> ' . $to);
        return true;
    }

    $reason = 'brevo_http_error';
    if ($code === 401 || $code === 403) $reason = 'brevo_unauthorized';
    elseif ($code === 400) $reason = 'brevo_bad_request';
    elseif ($code === 429) $reason = 'brevo_rate_limited';
    elseif ($code >= 500) $reason = 'brevo_server_error';
    elseif ($code === 0) $reason = 'brevo_network_error';

    wbMailSetLastError($reason, 'brevo_api', (string)$code);
    error_log('[wbMail BrevoAPI] HTTP ' . $code . ' -> ' . $resp);
    return false;
}

function _wbMailSmtp(array $cfg, string $to, string $toName, string $subject, string $html, string $text): bool
{
    $host = (string)$cfg['host'];
    $port = (int)$cfg['port'];
    $user = (string)$cfg['username'];
    $pass = (string)$cfg['password'];
    $from = (string)$cfg['from_email'];
    $fromName = (string)$cfg['from_name'];
    $enc = strtolower((string)($cfg['encryption'] ?? 'tls'));

    $errno = 0;
    $errstr = '';
    $proto = ($enc === 'ssl') ? 'ssl' : 'tcp';
    $socket = @stream_socket_client("{$proto}://{$host}:{$port}", $errno, $errstr, 15);

    if (!$socket) {
        error_log("[wbMail SMTP] Connect failed ({$host}:{$port}): {$errstr} ({$errno})");
        wbMailSetLastError('smtp_connect_failed', 'smtp', "{$errstr} ({$errno})");
        return false;
    }

    stream_set_timeout($socket, 20);

    $readResp = function () use ($socket): string {
        $out = '';
        while (!feof($socket)) {
            $line = fgets($socket, 1024);
            if ($line === false) break;
            $out .= $line;
            if (strlen($line) >= 4 && $line[3] === ' ') break;
        }
        return $out;
    };

    $sendCmd = function (string $c) use ($socket, $readResp): string {
        fwrite($socket, $c . "\r\n");
        return $readResp();
    };

    $r = trim($readResp());
    if (!str_starts_with($r, '220')) { wbMailSetLastError('smtp_greeting_failed', 'smtp', $r); fclose($socket); return false; }

    $myHost = gethostname() ?: 'localhost';
    $r = trim($sendCmd("EHLO {$myHost}"));
    if (!str_starts_with($r, '250')) { wbMailSetLastError('smtp_ehlo_failed', 'smtp', $r); fclose($socket); return false; }

    if ($enc === 'tls') {
        $r = trim($sendCmd("STARTTLS"));
        if (!str_starts_with($r, '220')) { wbMailSetLastError('smtp_starttls_failed', 'smtp', $r); fclose($socket); return false; }
        if (!stream_socket_enable_crypto($socket, true, STREAM_CRYPTO_METHOD_TLS_CLIENT)) {
            wbMailSetLastError('smtp_tls_failed', 'smtp', 'TLS upgrade failed');
            fclose($socket);
            return false;
        }
        $r = trim($sendCmd("EHLO {$myHost}"));
        if (!str_starts_with($r, '250')) { wbMailSetLastError('smtp_ehlo_tls_failed', 'smtp', $r); fclose($socket); return false; }
    }

    $r = trim($sendCmd("AUTH LOGIN"));
    if (!str_starts_with($r, '334')) { wbMailSetLastError('smtp_auth_init_failed', 'smtp', $r); fclose($socket); return false; }
    $r = trim($sendCmd(base64_encode($user)));
    if (!str_starts_with($r, '334')) { wbMailSetLastError('smtp_auth_user_failed', 'smtp', $r); fclose($socket); return false; }
    $r = trim($sendCmd(base64_encode($pass)));
    if (!str_starts_with($r, '235')) { wbMailSetLastError('smtp_auth_failed', 'smtp', $r); fclose($socket); return false; }

    $r = trim($sendCmd("MAIL FROM:<{$from}>"));
    if (!str_starts_with($r, '250')) { wbMailSetLastError('smtp_mail_from_failed', 'smtp', $r); fclose($socket); return false; }
    $r = trim($sendCmd("RCPT TO:<{$to}>"));
    if (!str_starts_with($r, '250')) { wbMailSetLastError('smtp_rcpt_failed', 'smtp', $r); fclose($socket); return false; }
    $r = trim($sendCmd("DATA"));
    if (!str_starts_with($r, '354')) { wbMailSetLastError('smtp_data_failed', 'smtp', $r); fclose($socket); return false; }

    $boundary = '----=_WbPart_' . bin2hex(random_bytes(8));
    $msgId = '<' . bin2hex(random_bytes(10)) . '@webey>';
    $fromEnc = '=?UTF-8?B?' . base64_encode($fromName) . '?=';
    $toEnc = $toName ? ('=?UTF-8?B?' . base64_encode($toName) . '?= <' . $to . '>') : $to;
    $subjEnc = '=?UTF-8?B?' . base64_encode($subject) . '?=';

    $msg = "Date: " . date('r') . "\r\n";
    $msg .= "From: {$fromEnc} <{$from}>\r\n";
    $msg .= "To: {$toEnc}\r\n";
    $msg .= "Subject: {$subjEnc}\r\n";
    $msg .= "Message-ID: {$msgId}\r\n";
    $msg .= "MIME-Version: 1.0\r\n";
    $msg .= "Content-Type: multipart/alternative; boundary=\"{$boundary}\"\r\n";
    $msg .= "X-Mailer: Webey\r\n\r\n";
    $msg .= "--{$boundary}\r\n";
    $msg .= "Content-Type: text/plain; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\n";
    $msg .= rtrim(chunk_split(base64_encode($text), 76, "\r\n")) . "\r\n\r\n";
    $msg .= "--{$boundary}\r\n";
    $msg .= "Content-Type: text/html; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\n";
    $msg .= rtrim(chunk_split(base64_encode($html), 76, "\r\n")) . "\r\n\r\n";
    $msg .= "--{$boundary}--";
    $msg = preg_replace('/^\\.$/m', '..', $msg);

    fwrite($socket, $msg . "\r\n.\r\n");
    $r = trim($readResp());
    if (!str_starts_with($r, '250')) {
        wbMailSetLastError('smtp_send_failed', 'smtp', $r);
        fclose($socket);
        return false;
    }

    $sendCmd("QUIT");
    fclose($socket);
    return true;
}

function _wbMailPHPMailer(array $cfg, string $to, string $toName, string $subject, string $html, string $text): bool
{
    require_once __DIR__ . '/../../vendor/autoload.php';
    try {
        $mail = new PHPMailer\PHPMailer\PHPMailer(true);
        $mail->isSMTP();
        $mail->Host = (string)$cfg['host'];
        $mail->SMTPAuth = true;
        $mail->Username = (string)$cfg['username'];
        $mail->Password = (string)$cfg['password'];
        $mail->SMTPSecure = strtolower((string)$cfg['encryption']) === 'ssl'
            ? PHPMailer\PHPMailer\PHPMailer::ENCRYPTION_SMTPS
            : PHPMailer\PHPMailer\PHPMailer::ENCRYPTION_STARTTLS;
        $mail->Port = (int)$cfg['port'];
        $mail->CharSet = 'UTF-8';
        $mail->SMTPDebug = 0;
        $mail->setFrom((string)$cfg['from_email'], (string)$cfg['from_name']);
        $mail->addAddress($to, $toName);
        $mail->isHTML(true);
        $mail->Subject = $subject;
        $mail->Body = $html;
        $mail->AltBody = $text;
        $mail->send();
        return true;
    } catch (Throwable $e) {
        error_log('[wbMail PHPMailer] ' . $e->getMessage());
        wbMailSetLastError('phpmailer_exception', 'phpmailer', $e->getMessage());
        return false;
    }
}
