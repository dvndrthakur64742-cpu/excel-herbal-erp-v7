<?php
namespace ExcelHerbal\ERP7\Security;
final class BranchScope {
    /** @param int[] $effectiveBranchIds */
    public static function projection(int $assignedBranchId, array $effectiveBranchIds): array {
        $ids = array_values(array_unique(array_filter(array_map('intval', $effectiveBranchIds), fn($id) => $id > 0)));
        if ($assignedBranchId > 0 && !in_array($assignedBranchId, $ids, true)) $ids[] = $assignedBranchId;
        sort($ids);
        return [
            'assigned_branch_id' => $assignedBranchId,
            'branch_ids' => $ids,
            'selector_visible' => count($ids) > 1,
        ];
    }
}
