<?php
namespace ExcelHerbal\ERP7\Organization;

/**
 * Pure, read-only classification for the employee login repair screen.
 * A candidate is never authorization to link an existing WP user or reset a password.
 */
final class EmployeeLoginPreflight {
    public static function assess(
        string $employeeStatus,
        int $linkedUserId,
        bool $linkedUserExists,
        bool $linkedUserPrivileged,
        string $normalizedMobile,
        bool $mobileUsernameTaken,
        bool $employeeEmailTaken,
        bool $sharedWpIdentity = false
    ):array {
        $linked = $linkedUserId > 0 && $linkedUserExists;
        $identity = $linked ? 'linked' : ($linkedUserId > 0 ? 'broken' : 'unlinked');
        $active = strtolower(trim($employeeStatus)) === 'active';
        $mobileValid = preg_match('/^[0-9]{8,15}$/D', $normalizedMobile) === 1;
        $blockers = [];
        if (!$active) $blockers[]='employee_inactive';
        if (!$mobileValid) $blockers[]='mobile_missing_or_invalid';
        if ($linked && $linkedUserPrivileged) $blockers[]='privileged_wordpress_identity';
        if ($sharedWpIdentity) $blockers[]='wp_identity_duplicate_link';
        if (!$linked && $mobileValid && $mobileUsernameTaken) $blockers[]='mobile_username_claimed';
        if (!$linked && $employeeEmailTaken) $blockers[]='employee_email_claimed';
        return [
            'identity_state'=>$identity,
            'mobile_valid'=>$mobileValid,
            'can_reset_subscriber_password'=>$active && $linked && !$linkedUserPrivileged && !$sharedWpIdentity && $mobileValid,
            'new_subscriber_candidate'=>$active && !$linked && !$sharedWpIdentity && $mobileValid && !$mobileUsernameTaken && !$employeeEmailTaken,
            'identity_owner_verification_required'=>true,
            'blockers'=>$blockers,
        ];
    }
}
