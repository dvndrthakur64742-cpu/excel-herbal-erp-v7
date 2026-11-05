<?php
namespace ExcelHerbal\ERP7\Organization;

use ExcelHerbal\ERP7\Domain\DomainException;

/**
 * Auditable acknowledgement of an independently verified employee identity.
 * This is not proof that an actual person was verified; the operator remains
 * responsible for confirming ownership through an approved offline procedure.
 */
final class EmployeeIdentityAttestation {
    /** @return array{method:string,reference:string} */
    public static function requireForCredentialChange(array $data):array {
        if(($data['identity_verified']??null)!==true){
            throw new DomainException('Employee identity confirmation is required before changing login credentials.','employee_identity_confirmation_required',422);
        }
        $method=strtolower(trim((string)($data['verification_method']??'')));
        if(!in_array($method,['in_person','registered_mobile_callback'],true)){
            throw new DomainException('Select an approved manual employee identity verification method.','employee_verification_method_invalid',422);
        }
        $reference=trim((string)($data['verification_reference']??''));
        // A case/ticket reference, not a phone number, government ID or password.
        if(!preg_match('/^[A-Za-z][A-Za-z0-9_.-]{5,63}$/D',$reference)){
            throw new DomainException('Enter a valid internal verification case reference (6–64 characters, starting with a letter).','employee_verification_reference_invalid',422);
        }
        return ['method'=>$method,'reference'=>$reference];
    }
}
