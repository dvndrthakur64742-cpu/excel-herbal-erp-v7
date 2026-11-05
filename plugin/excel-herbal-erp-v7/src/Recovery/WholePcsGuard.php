<?php
declare(strict_types=1);

namespace ExcelHerbal\ERP7\Recovery;

use InvalidArgumentException;

final class WholePcsGuard
{
    /** @var array<string,bool> */
    private const QUANTITY_KEYS = [
        'quantity' => true,
        'issued_quantity' => true,
        'retail_quantity' => true,
        'return_quantity' => true,
        'wholesale_quantity' => true,
        'received_quantity' => true,
        'quantity_delta' => true,
    ];

    public static function assertWhole(mixed $value, string $field = 'quantity', bool $allowNegative = false): int
    {
        if (is_int($value)) {
            $number = $value;
        } elseif (is_float($value)) {
            if (!is_finite($value) || floor($value) !== $value) {
                throw new InvalidArgumentException("{$field} must be whole PCS.");
            }
            $number = (int) $value;
        } elseif (is_string($value) && preg_match('/^-?\d+$/D', trim($value)) === 1) {
            $number = (int) trim($value);
        } else {
            throw new InvalidArgumentException("{$field} must be whole PCS.");
        }

        if (!$allowNegative && $number < 0) {
            throw new InvalidArgumentException("{$field} cannot be negative.");
        }

        return $number;
    }

    /**
     * Validates only stock/product quantity fields. Money, GPS coordinates,
     * percentage, tax and rate fields are intentionally untouched.
     *
     * @param array<string,mixed> $payload
     */
    public static function validatePayload(array $payload): void
    {
        self::walk($payload);
    }

    /** @param array<string|int,mixed> $node */
    private static function walk(array $node): void
    {
        foreach ($node as $key => $value) {
            if (is_array($value)) {
                self::walk($value);
                continue;
            }
            if (!is_string($key) || !isset(self::QUANTITY_KEYS[$key])) {
                continue;
            }
            self::assertWhole($value, $key, $key === 'quantity_delta');
        }
    }
}
