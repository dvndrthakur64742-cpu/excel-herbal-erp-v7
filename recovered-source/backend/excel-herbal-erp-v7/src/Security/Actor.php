<?php
namespace ExcelHerbal\ERP7\Security;
final class Actor {
    /** @param int[] $branchIds @param string[] $capabilities */
    public function __construct(public readonly int $userId,public readonly int $employeeId,public readonly int $companyId,public readonly int $assignedBranchId,public readonly array $branchIds,public readonly array $capabilities,public readonly string $designationCode){}
    public function can(string $cap): bool{return in_array($cap,$this->capabilities,true);} public function hasBranch(int $id):bool{return in_array($id,$this->branchIds,true);} public function selectorVisible():bool{return count($this->branchIds)>1;}
}
