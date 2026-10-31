<?php
declare(strict_types=1);

namespace ExcelHerbal\ERP7\Recovery;

final class AppVersionPolicy
{
    /** @param array<string,string|null> $settings */
    public static function project(array $settings, int $clientBuild = 0): array
    {
        $minimumBuild = max(0, (int)($settings['app.android.minimum_build'] ?? 0));
        $latestBuild = max($minimumBuild, (int)($settings['app.android.latest_build'] ?? $minimumBuild));
        return [
            'minimum_build' => $minimumBuild,
            'latest_build' => $latestBuild,
            'minimum_version' => (string)($settings['app.android.minimum_version'] ?? ''),
            'latest_version' => (string)($settings['app.android.latest_version'] ?? ''),
            'update_url' => (string)($settings['app.android.update_url'] ?? ''),
            'message' => (string)($settings['app.android.update_message'] ?? 'App update required.'),
            'force_update' => $clientBuild > 0 && $minimumBuild > 0 && $clientBuild < $minimumBuild,
            'update_available' => $clientBuild > 0 && $latestBuild > 0 && $clientBuild < $latestBuild,
        ];
    }
}
