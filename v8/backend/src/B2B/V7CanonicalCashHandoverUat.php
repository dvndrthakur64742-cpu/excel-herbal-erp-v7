<?php
declare(strict_types=1);
namespace ExcelHerbal\ERP8\B2B;

use Closure;
use ExcelHerbal\ERP7\Database\{Db,Transaction};
use ExcelHerbal\ERP7\Finance\{AccountingService,BranchDayGuard};
use ExcelHerbal\ERP7\Security\{Actor,Capabilities,Guard};

/**
 * DISPOSABLE v8_test ONLY. No WordPress route or production schema installation.
 * Independent cashier attestation -> one canonical V7 journal reclassification.
 * This is NOT another retail sale, payment proof, stock movement or shadow GL.
 *
 * $authority is a server-supplied callable validating the cashier's authenticated
 * session and actual role; no request-supplied actor/cashier flag is accepted.
 */
final class V7CanonicalCashHandoverUat
{
    public function __construct(private Actor $actor, private Closure $authority) {}

    private function gate(int $branch,string $action):void
    {
        V7CanonicalPostingSinkUat::assertNonProductionEnvironment(Db::wpdb());
        Guard::branch($this->actor,$branch,Capabilities::ACCOUNTING_VIEW);
        if (($this->authority)($action,$this->actor->userId,$this->actor->companyId,$branch)!==true) {
            throw new RetailerSaleError('Independent cashier financial authority denied.');
        }
    }

    private static function money(int $paise):string
    {
        if($paise<1 || $paise>99999999999999)
            throw new RetailerSaleError('Canonical Cash amount invalid.');
        return intdiv($paise,100).'.'.str_pad((string)($paise%100),2,'0',STR_PAD_LEFT);
    }

    /** Locks canonical posted field cash sale and its original employee-tagged GL. */
    private function lockedSale(int $branch,int $saleId):array
    {
        $db=Db::wpdb();
        $r=$db->get_row($db->prepare(
            'SELECT * FROM '.Db::table('b2b_retailer_sales').
            ' WHERE id=%d AND company_id=%d AND branch_id=%d FOR UPDATE',
            $saleId,$this->actor->companyId,$branch
        ),ARRAY_A);
        if(!is_array($r)||($r['status']??null)!=='posted'
            ||($r['channel']??null)!=='field'||($r['payment_mode']??null)!=='cash'
            ||(int)($r['employee_id']??0)<1||(int)($r['outstanding_paise']??-1)!==0
            ||(int)($r['invoice_total_paise']??0)<1||(int)($r['journal_entry_id']??0)<1) {
            throw new RetailerSaleError('Only an originally posted field Cash sale can be handed over.');
        }
        $r['id']=(int)$r['id'];$r['employee_id']=(int)$r['employee_id'];
        $r['amount_paise']=(int)$r['invoice_total_paise'];
        $r['journal_entry_id']=(int)$r['journal_entry_id'];
        if($r['employee_id']===$this->actor->employeeId||(int)$r['created_by']===$this->actor->employeeId)
            throw new RetailerSaleError('Field sale maker cannot attest or self-remit Cash.');
        $header=$db->get_row($db->prepare(
            'SELECT id FROM '.Db::table('journal_entries').
            " WHERE id=%d AND company_id=%d AND branch_id=%d AND source_type='b2b_retailer_sale' ".
            "AND source_id=%d AND status='posted' FOR UPDATE",
            $r['journal_entry_id'],$this->actor->companyId,$branch,$r['id']
        ),ARRAY_A);
        if(!is_array($header)) throw new RetailerSaleError('Original canonical Cash GL journal missing.');
        $transit=$db->get_row($db->prepare(
            'SELECT COUNT(*) lines,COALESCE(SUM(jl.debit),0) debit,COALESCE(SUM(jl.credit),0) credit '.
            'FROM '.Db::table('journal_lines').' jl JOIN '.Db::table('accounts').
            ' a ON a.id=jl.account_id AND a.company_id=%d '.
            "WHERE jl.journal_entry_id=%d AND a.code='EMPLOYEE_CASH_IN_TRANSIT' ".
            "AND jl.party_type='employee' AND jl.party_id=%d",
            $this->actor->companyId,$r['journal_entry_id'],$r['employee_id']
        ),ARRAY_A);
        if(!is_array($transit)||(int)$transit['lines']!==1
            ||Paise::parse((string)$transit['debit'])!==$r['amount_paise']
            ||Paise::parse((string)$transit['credit'])!==0)
            throw new RetailerSaleError('Original employee Cash-in-Transit GL debit not verified.');
        return $r;
    }

    private static function receipt(int $company,int $branch,int $sale):?array
    {
        $db=Db::wpdb();
        $r=$db->get_row($db->prepare(
            'SELECT * FROM '.Db::table('b2b_cashier_receipts_uat').
            ' WHERE company_id=%d AND branch_id=%d AND sale_id=%d FOR UPDATE',
            $company,$branch,$sale
        ),ARRAY_A);
        return is_array($r)?$r:null;
    }

    /** Physical full-amount acknowledgement by independently authenticated cashier. */
    public function attest(int $branch,int $saleId,string $reference):array
    {
        if($saleId<1||!preg_match('/^[A-Za-z0-9][A-Za-z0-9._:\/-]{7,127}$/D',$reference))
            throw new RetailerSaleError('Valid field Cash sale and receipt reference required.');
        $this->gate($branch,'cash_receipt.attest');
        return Transaction::run(function()use($branch,$saleId,$reference):array {
            $this->gate($branch,'cash_receipt.attest');
            AccountingService::lockCompanyForPeriod($this->actor);
            AccountingService::assertPeriodOpen($this->actor,Db::today());
            BranchDayGuard::assertOpen($this->actor,$branch,Db::today());
            $sale=$this->lockedSale($branch,$saleId);
            $db=Db::wpdb();
            $company=$this->actor->companyId;
            $existing=self::receipt($company,$branch,$saleId);
            if($existing!==null){
                if((string)$existing['receipt_reference']!==$reference
                    ||(int)$existing['cashier_user_id']!==$this->actor->userId
                    ||(int)$existing['cashier_employee_id']!==$this->actor->employeeId
                    ||(int)$existing['employee_id']!==$sale['employee_id']
                    ||(int)$existing['amount_paise']!==$sale['amount_paise']
                    ||(string)$existing['status']!=='confirmed')
                    throw new RetailerSaleError('Cash receipt already attested with different details.');
                return ['receipt_id'=>(int)$existing['id'],
                    'amount_paise'=>$sale['amount_paise'],
                    'already_attested'=>true,'consumed'=>($existing['consumed_remittance_id']!==null)];
            }
            Db::mustInsert($db,Db::table('b2b_cashier_receipts_uat'),[
                'company_id'=>$company,'branch_id'=>$branch,'sale_id'=>$saleId,
                'employee_id'=>$sale['employee_id'],
                'cashier_employee_id'=>$this->actor->employeeId,'cashier_user_id'=>$this->actor->userId,
                'receipt_reference'=>$reference,'amount_paise'=>$sale['amount_paise'],
                'status'=>'confirmed','received_at'=>Db::now()
            ]);
            return ['receipt_id'=>(int)$db->insert_id,'amount_paise'=>$sale['amount_paise'],
                'already_attested'=>false,'consumed'=>false];
        });
    }

    private function existingVerifiedJournal(array $row,int $amount,int $employee):int
    {
        $db=Db::wpdb();$journal=(int)($row['journal_entry_id']??0);
        if(($row['status']??null)!=='posted'||$journal<1)
            throw new RetailerSaleError('Previously posted Cash remittance is incomplete.');
        $h=$db->get_row($db->prepare('SELECT id FROM '.Db::table('journal_entries').
            " WHERE id=%d AND company_id=%d AND source_type='b2b_cash_remittance' ".
            "AND source_id=%d AND status='posted' FOR UPDATE",
            $journal,$this->actor->companyId,(int)$row['id']),ARRAY_A);
        $lines=$db->get_results($db->prepare(
            'SELECT a.code,jl.debit,jl.credit,jl.party_type,jl.party_id FROM '.
            Db::table('journal_lines').' jl JOIN '.Db::table('accounts').
            ' a ON a.id=jl.account_id AND a.company_id=%d WHERE jl.journal_entry_id=%d ORDER BY jl.id',
            $this->actor->companyId,$journal
        ),ARRAY_A);
        if(!$h||!is_array($lines)||count($lines)!==2)throw new RetailerSaleError('Cash remittance GL replay cannot be verified.');
        $found=[];
        foreach($lines as $l)$found[(string)$l['code']]=$l;
        $branch=$found['BRANCH_CASH']??null;$transit=$found['EMPLOYEE_CASH_IN_TRANSIT']??null;
        if(count($found)!==2||!$branch||!$transit
            ||Paise::parse((string)$branch['debit'])!==$amount
            ||Paise::parse((string)$branch['credit'])!==0
            ||Paise::parse((string)$transit['credit'])!==$amount
            ||Paise::parse((string)$transit['debit'])!==0
            ||$transit['party_type']!=='employee'
            ||(int)$transit['party_id']!==$employee)
            throw new RetailerSaleError('Cash remittance GL is inconsistent with cashier evidence.');
        return $journal;
    }

    /** Post ONE canonical V7 journal: Dr BRANCH_CASH / Cr EMPLOYEE_CASH_IN_TRANSIT. */
    public function post(int $branch,int $saleId,string $key):array
    {
        if($saleId<1||!preg_match('/^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$/D',$key))
            throw new RetailerSaleError('Valid trusted Cash remittance idempotency key required.');
        $this->gate($branch,'cash_remittance.post');
        return Transaction::run(function()use($branch,$saleId,$key):array {
            $this->gate($branch,'cash_remittance.post');
            AccountingService::lockCompanyForPeriod($this->actor);
            AccountingService::assertPeriodOpen($this->actor,Db::today());
            BranchDayGuard::assertOpen($this->actor,$branch,Db::today());
            $sale=$this->lockedSale($branch,$saleId);
            $db=Db::wpdb();$company=$this->actor->companyId;
            $receipt=self::receipt($company,$branch,$saleId);
            if(!$receipt||$receipt['status']!=='confirmed'
                ||(int)$receipt['amount_paise']!==$sale['amount_paise']
                ||(int)$receipt['employee_id']!==$sale['employee_id']
                ||(int)$receipt['cashier_employee_id']===$sale['employee_id']
                ||(int)$receipt['cashier_employee_id']===(int)$sale['created_by']
                ||(int)$receipt['cashier_user_id']<1)
                throw new RetailerSaleError('Independent exact-amount cashier receipt missing.');
            $fingerprint=hash('sha256',json_encode([
                $company,$branch,$saleId,(int)$receipt['id'],$this->actor->userId,$key
            ],JSON_THROW_ON_ERROR));
            $prior=$db->get_row($db->prepare('SELECT * FROM '.Db::table('b2b_cash_remittances').
                ' WHERE company_id=%d AND sale_id=%d FOR UPDATE',$company,$saleId),ARRAY_A);
            if(is_array($prior)){
                if($prior['request_key']!==$key
                    ||!hash_equals((string)$prior['request_fingerprint'],$fingerprint)
                    ||(int)$prior['receipt_id']!==(int)$receipt['id']
                    ||(int)$prior['amount_paise']!==$sale['amount_paise']
                    ||(int)$receipt['consumed_remittance_id']!==(int)$prior['id'])
                    throw new RetailerSaleError('Duplicate or altered Cash remittance attempt.');
                $journal=$this->existingVerifiedJournal($prior,$sale['amount_paise'],$sale['employee_id']);
                return ['remittance_id'=>(int)$prior['id'],'journal_id'=>$journal,
                    'sale_id'=>$saleId,'employee_id'=>$sale['employee_id'],
                    'amount_paise'=>$sale['amount_paise'],'status'=>'posted','replayed'=>true];
            }
            if($receipt['consumed_remittance_id']!==null)
                throw new RetailerSaleError('Cashier receipt already consumed.');
            Db::mustInsert($db,Db::table('b2b_cash_remittances'),[
                'company_id'=>$company,'branch_id'=>$branch,'sale_id'=>$saleId,
                'employee_id'=>$sale['employee_id'],'receipt_id'=>(int)$receipt['id'],
                'cashier_employee_id'=>$this->actor->employeeId,
                'amount_paise'=>$sale['amount_paise'],'request_key'=>$key,
                'request_fingerprint'=>$fingerprint,'journal_entry_id'=>null,
                'status'=>'pending','created_at'=>Db::now()
            ]);
            $id=(int)$db->insert_id;
            $branchCash=AccountingService::accountByCode($this->actor,'BRANCH_CASH');
            $transit=AccountingService::accountByCode($this->actor,'EMPLOYEE_CASH_IN_TRANSIT');
            if(($branchCash['type']??null)!=='asset'
                ||($branchCash['subtype']??null)!=='cash'
                ||($transit['type']??null)!=='asset')
                throw new RetailerSaleError('Canonical Cash/Transit Chart of Accounts invalid.');
            $money=self::money($sale['amount_paise']);
            $journal=AccountingService::post($this->actor,$branch,'b2b_cash_remittance',$id,Db::businessNow(),[
                ['account_id'=>(int)$branchCash['id'],'debit'=>$money,'credit'=>0],
                ['account_id'=>(int)$transit['id'],'debit'=>0,'credit'=>$money,
                 'party_type'=>'employee','party_id'=>$sale['employee_id'],
                 'description'=>'Independent cashier handover of employee field cash']
            ],'Field Cash handover from employee #'.$sale['employee_id'].'; original sale #'.$saleId);
            if($journal<1)throw new RetailerSaleError('Canonical Cash reclassification journal failed.');
            $updated=Db::mustUpdate($db,Db::table('b2b_cash_remittances'),
                ['status'=>'posted','journal_entry_id'=>$journal],['id'=>$id,'status'=>'pending']);
            $consumed=Db::mustUpdate($db,Db::table('b2b_cashier_receipts_uat'),
                ['consumed_remittance_id'=>$id],['id'=>(int)$receipt['id'],'consumed_remittance_id'=>null]);
            if($updated!==1||$consumed!==1)
                throw new RetailerSaleError('Atomic Cash handover receipt consumption failed.');
            $this->existingVerifiedJournal(['id'=>$id,'status'=>'posted','journal_entry_id'=>$journal],
                $sale['amount_paise'],$sale['employee_id']);
            return ['remittance_id'=>$id,'journal_id'=>$journal,'sale_id'=>$saleId,
                'employee_id'=>$sale['employee_id'],'amount_paise'=>$sale['amount_paise'],
                'status'=>'posted','replayed'=>false];
        });
    }
}
