<?php
// Pure identity acknowledgement guard. Never uses real employee data or passwords.
require_once __DIR__.'/../src/Core/Autoloader.php';
\ExcelHerbal\ERP7\Core\Autoloader::register(__DIR__.'/../src');

use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Organization\EmployeeIdentityAttestation;

function expectAttestationReject(array $data,string $code):void{
    try{EmployeeIdentityAttestation::requireForCredentialChange($data);}
    catch(DomainException $e){
        if($e->codeKey!==$code)throw new RuntimeException('Unexpected code '.$e->codeKey);
        echo 'PASS reject '.$code.PHP_EOL;return;
    }
    throw new RuntimeException('Unexpected acceptance: '.$code);
}
expectAttestationReject([], 'employee_identity_confirmation_required');
expectAttestationReject(['identity_verified'=>'true','verification_method'=>'in_person','verification_reference'=>'HR-CASE-123'], 'employee_identity_confirmation_required');
expectAttestationReject(['identity_verified'=>true,'verification_method'=>'sms_otp','verification_reference'=>'HR-CASE-123'], 'employee_verification_method_invalid');
expectAttestationReject(['identity_verified'=>true,'verification_method'=>'in_person','verification_reference'=>'9000000011'], 'employee_verification_reference_invalid');
expectAttestationReject(['identity_verified'=>true,'verification_method'=>'in_person','verification_reference'=>'HR A Person'], 'employee_verification_reference_invalid');
foreach(['in_person','registered_mobile_callback'] as $method){
    $x=EmployeeIdentityAttestation::requireForCredentialChange(['identity_verified'=>true,'verification_method'=>$method,'verification_reference'=>'HR-CASE-123']);
    if($x!==['method'=>$method,'reference'=>'HR-CASE-123'])throw new RuntimeException('Wrong normalized attestation');
    echo 'PASS valid '.$method.PHP_EOL;
}
$service=file_get_contents(__DIR__.'/../src/Organization/OrganizationEmployeeService.php');
$admin=file_get_contents(__DIR__.'/../src/Admin/Dashboard.php');
if(!str_contains($service,'EmployeeIdentityAttestation::requireForCredentialChange($data)')||
   !str_contains($service,"'verification_reference'=>\$verified['reference']")||
   !str_contains($service,'Guard::cap($a,Capabilities::ACCESS_MANAGE)')){
    throw new RuntimeException('Identity confirmation not enforced in credential service');
}
foreach(['identity_verified:true','verification_method:method.value','verification_reference:verifyRef.value.trim()','eh7-identity-verified','eh7-verify-ref'] as $needle){
    if(!str_contains($admin,$needle))throw new RuntimeException('WordPress admin UI missing '. $needle);
}
echo 'PASS service + WP admin attestation integration'.PHP_EOL;
