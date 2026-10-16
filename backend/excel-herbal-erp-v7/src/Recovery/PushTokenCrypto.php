<?php
declare(strict_types=1);

namespace ExcelHerbal\ERP7\Recovery;

use RuntimeException;

final class PushTokenCrypto
{
    /** @return array{hash:string,ciphertext:string,iv:string,tag:string} */
    public static function protect(string $token, string $secret): array
    {
        $token = trim($token);
        if ($token === '') {
            throw new RuntimeException('Push token required.');
        }
        if (!function_exists('openssl_encrypt')) {
            throw new RuntimeException('OpenSSL extension required for push-token protection.');
        }
        $key = hash('sha256', $secret, true);
        $iv = random_bytes(12);
        $tag = '';
        $ciphertext = openssl_encrypt($token, 'aes-256-gcm', $key, OPENSSL_RAW_DATA, $iv, $tag);
        if ($ciphertext === false) {
            throw new RuntimeException('Push-token encryption failed.');
        }
        return [
            'hash' => hash('sha256', $token),
            'ciphertext' => base64_encode($ciphertext),
            'iv' => base64_encode($iv),
            'tag' => base64_encode($tag),
        ];
    }

    public static function reveal(string $ciphertext, string $iv, string $tag, string $secret): string
    {
        $key = hash('sha256', $secret, true);
        $plain = openssl_decrypt(
            base64_decode($ciphertext, true) ?: '',
            'aes-256-gcm',
            $key,
            OPENSSL_RAW_DATA,
            base64_decode($iv, true) ?: '',
            base64_decode($tag, true) ?: ''
        );
        if ($plain === false) {
            throw new RuntimeException('Push-token decryption failed.');
        }
        return $plain;
    }
}
