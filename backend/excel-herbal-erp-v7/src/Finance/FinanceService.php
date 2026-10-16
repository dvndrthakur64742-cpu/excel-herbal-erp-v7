<?php
namespace ExcelHerbal\ERP7\Finance;
use ExcelHerbal\ERP7\Security\Actor;
/** Backwards-compatible route facade; domain behavior lives in focused services. */
final class FinanceService{
 public static function bootstrap(Actor $a):array{return FinanceAccountService::bootstrap($a);}
 public static function createAccount(Actor $a,string $code,string $name,string $type,string $subtype=''):array{return FinanceAccountService::createAccount($a,$code,$name,$type,$subtype);}
 public static function createExpenseHead(Actor $a,string $code,string $name,int $accountId):array{return FinanceAccountService::createExpenseHead($a,$code,$name,$accountId);}
 public static function expenses(Actor $a,int $branch):array{return FinanceExpenseService::expenses($a,$branch);}
 public static function closings(Actor $a,int $branch):array{return FinanceClosingService::closings($a,$branch);}
 public static function periods(Actor $a):array{return FinancePeriodService::periods($a);}
 public static function bankReconciliations(Actor $a,int $branch):array{return FinanceBankService::bankReconciliations($a,$branch);}
 public static function expense(Actor $a,int $branch,int $head,float $amount,int $account,string $date,string $desc):array{return FinanceExpenseService::expense($a,$branch,$head,$amount,$account,$date,$desc);}
 public static function expenseDecision(Actor $a,int $id,bool $approve):array{return FinanceExpenseService::expenseDecision($a,$id,$approve);}
 public static function closingPreflight(Actor $a,int $branch,string $date):array{return FinanceClosingService::closingPreflight($a,$branch,$date);}
 public static function closingDraft(Actor $a,int $branch,string $date):array{return FinanceClosingService::closingDraft($a,$branch,$date);}
 public static function closeBranch(Actor $a,int $id):array{return FinanceClosingService::closeBranch($a,$id);}
 public static function reopenBranch(Actor $a,int $id,string $reason):array{return FinanceClosingService::reopenBranch($a,$id,$reason);}
 public static function reversals(Actor $a,string $status=''):array{return FinanceReversalService::reversals($a,$status);}
 public static function requestReversal(Actor $a,string $type,int $source,string $reason):array{return FinanceReversalService::requestReversal($a,$type,$source,$reason);}
 public static function reversalDecision(Actor $a,int $id,bool $approve):array{return FinanceReversalService::reversalDecision($a,$id,$approve);}
 public static function executeReversal(Actor $a,int $id):array{return FinanceReversalService::executeReversal($a,$id);}
 public static function closePeriod(Actor $a,string $from,string $to):array{return FinancePeriodService::closePeriod($a,$from,$to);}
 public static function reopenPeriod(Actor $a,int $id,string $reason):array{return FinancePeriodService::reopenPeriod($a,$id,$reason);}
 public static function bankDetail(Actor $a,int $id):array{return FinanceBankService::bankDetail($a,$id);}
 public static function bankCreate(Actor $a,int $branch,int $account,string $from,string $to,float $opening,float $closing):array{return FinanceBankService::bankCreate($a,$branch,$account,$from,$to,$opening,$closing);}
 public static function bankImport(Actor $a,int $id,array $lines):array{return FinanceBankService::bankImport($a,$id,$lines);}
 public static function bankMatch(Actor $a,int $line,int $journalLine):array{return FinanceBankService::bankMatch($a,$line,$journalLine);}
 public static function bankExclude(Actor $a,int $line,string $reason):array{return FinanceBankService::bankExclude($a,$line,$reason);}
 public static function bankFinalize(Actor $a,int $id):array{return FinanceBankService::bankFinalize($a,$id);}
}
