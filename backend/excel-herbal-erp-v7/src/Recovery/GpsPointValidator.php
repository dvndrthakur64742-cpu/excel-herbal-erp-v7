<?php
declare(strict_types=1);

namespace ExcelHerbal\ERP7\Recovery;

use InvalidArgumentException;

final class GpsPointValidator
{
    /** @param array<string,mixed> $data */
    public static function normalize(array $data): array
    {
        $lat = filter_var($data['lat'] ?? $data['latitude'] ?? null, FILTER_VALIDATE_FLOAT);
        $lng = filter_var($data['lng'] ?? $data['longitude'] ?? null, FILTER_VALIDATE_FLOAT);
        if ($lat === false || $lat < -90 || $lat > 90) {
            throw new InvalidArgumentException('Valid GPS latitude required.');
        }
        if ($lng === false || $lng < -180 || $lng > 180) {
            throw new InvalidArgumentException('Valid GPS longitude required.');
        }
        $accuracy = $data['accuracy_m'] ?? $data['accuracy'] ?? null;
        if ($accuracy !== null && $accuracy !== '') {
            $accuracy = filter_var($accuracy, FILTER_VALIDATE_FLOAT);
            if ($accuracy === false || $accuracy < 0 || $accuracy > 10000) {
                throw new InvalidArgumentException('GPS accuracy is invalid.');
            }
        } else {
            $accuracy = null;
        }
        $source = strtolower(trim((string)($data['source'] ?? 'duty')));
        if (!in_array($source, ['duty','duty_web','field_visit','manual_retry'], true)) {
            throw new InvalidArgumentException('GPS point source is invalid.');
        }
        return [
            'latitude' => round((float)$lat, 7),
            'longitude' => round((float)$lng, 7),
            'accuracy_m' => $accuracy === null ? null : round((float)$accuracy, 2),
            'source' => $source,
        ];
    }
}
