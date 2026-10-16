<?php
namespace ExcelHerbal\ERP7\Domain;
final class DomainException extends \RuntimeException {
    public function __construct(string $message, public readonly string $codeKey='domain_error', public readonly int $httpStatus=422){parent::__construct($message);}
}
