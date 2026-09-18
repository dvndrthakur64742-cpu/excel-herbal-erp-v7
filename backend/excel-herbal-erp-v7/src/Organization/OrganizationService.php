<?php
namespace ExcelHerbal\ERP7\Organization;
use ExcelHerbal\ERP7\Security\Actor;use ExcelHerbal\ERP7\Security\Capabilities;
/** Backwards-compatible route facade; domain behavior lives in focused services. */
final class OrganizationService{
 public static function branches(Actor $a):array{return OrganizationBranchService::branches($a);}
 public static function createBranch(Actor $a,string $code,string $name,bool $headOffice=false):array{return OrganizationBranchService::createBranch($a,$code,$name,$headOffice);}
 public static function employees(Actor $a,int $branch,string $status='active'):array{return OrganizationEmployeeService::employees($a,$branch,$status);}
 public static function createEmployee(Actor $a,array $data,string $requiredCapability=Capabilities::EMP_MANAGE):array{return OrganizationEmployeeService::createEmployee($a,$data,$requiredCapability);}
 public static function setEmployeeCredentials(Actor $a,int $employeeId,array $data,string $requiredCapability=Capabilities::EMP_MANAGE):array{return OrganizationEmployeeService::setEmployeeCredentials($a,$employeeId,$data,$requiredCapability);}
 public static function employeeLoginStatus(Actor $a,int $employeeId):array{return OrganizationEmployeeService::employeeLoginStatus($a,$employeeId);}
 public static function revokeEmployeeSessions(Actor $a,int $employeeId):array{return OrganizationEmployeeService::revokeEmployeeSessions($a,$employeeId);}
 public static function reactivateEmployee(Actor $a,int $employeeId,?int $branchId,string $reactivationDate,string $reason):array{return OrganizationEmployeeService::reactivateEmployee($a,$employeeId,$branchId,$reactivationDate,$reason);}
 public static function setReportingManager(Actor $a,int $employeeId,?int $managerId,string $reason):array{return OrganizationEmployeeService::setReportingManager($a,$employeeId,$managerId,$reason);}
 public static function offboardingPreflight(Actor $a,int $employeeId,string $separationDate='',string $requiredCapability=Capabilities::EMP_MANAGE):array{return OrganizationEmployeeService::offboardingPreflight($a,$employeeId,$separationDate,$requiredCapability);}
 public static function offboardEmployee(Actor $a,int $employeeId,string $separationDate,string $reason,string $requiredCapability=Capabilities::EMP_MANAGE):array{return OrganizationEmployeeService::offboardEmployee($a,$employeeId,$separationDate,$reason,$requiredCapability);}
 public static function transferEmployee(Actor $a,int $employeeId,int $newBranch,string $effectiveDate,string $reason):array{return OrganizationEmployeeService::transferEmployee($a,$employeeId,$newBranch,$effectiveDate,$reason);}
 public static function employeeHistory(Actor $a,int $employeeId):array{return OrganizationEmployeeService::employeeHistory($a,$employeeId);}
 public static function designations(Actor $a):array{return OrganizationMasterDataService::designations($a);}
 public static function roles(Actor $a):array{return OrganizationMasterDataService::roles($a);}
 public static function masterData(Actor $a):array{return OrganizationMasterDataService::masterData($a);}
 public static function createProduct(Actor $a,array $data):array{return OrganizationProductService::createProduct($a,$data);}
 public static function commercialRevision(Actor $a,int $productId,array $data,string $reason=''):array{return OrganizationProductService::commercialRevision($a,$productId,$data,$reason);}
 public static function commercialHistory(Actor $a,int $productId):array{return OrganizationProductService::commercialHistory($a,$productId);}
 public static function setBranchAuthority(Actor $a,int $employeeId,int $branch,bool $active):array{return OrganizationBranchService::setBranchAuthority($a,$employeeId,$branch,$active);}
 public static function updateBranch(Actor $a,int $branchId,array $data):array{return OrganizationBranchService::updateBranch($a,$branchId,$data);}
 public static function setBranchStatus(Actor $a,int $branchId,bool $active):array{return OrganizationBranchService::setBranchStatus($a,$branchId,$active);}
 public static function updateEmployee(Actor $a,int $employeeId,array $data):array{return OrganizationEmployeeService::updateEmployee($a,$employeeId,$data);}
 public static function updateProduct(Actor $a,int $productId,array $data):array{return OrganizationProductService::updateProduct($a,$productId,$data);}
 public static function setProductStatus(Actor $a,int $productId,bool $active):array{return OrganizationProductService::setProductStatus($a,$productId,$active);}
 public static function employeeDesignations(Actor $a,int $employeeId):array{return OrganizationEmployeeService::employeeDesignations($a,$employeeId);}
 public static function assignEmployeeDesignation(Actor $a,int $employeeId,array $data):array{return OrganizationEmployeeService::assignEmployeeDesignation($a,$employeeId,$data);}
 public static function deactivateEmployeeDesignation(Actor $a,int $employeeId,int $assignmentId):array{return OrganizationEmployeeService::deactivateEmployeeDesignation($a,$employeeId,$assignmentId);}
}
