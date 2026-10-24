<?php
declare(strict_types=1);
namespace ExcelHerbal\ERP8\B2B;

use PDO;

/**
 * UAT-only employee Cash responsibility timeline sourced from existing
 * retailer sales, custody, independent cashier attestations and remittance
 * journals. Not a second GL, not an API and NOT canonical V7 accounting.
 *
 * Permission scope comes from the trusted server actor; no client-driven
 * query can infer a different employee's cash responsibility.
 */
final class UatEmployeeCashCustodyHistory
{
    public function __construct(private PDO $db, private $authorize)
    {
        if (!is_callable($authorize)) throw new RetailerSaleError('Finance viewer authorization required.');
        $this->db->setAttribute(PDO::ATTR_ERRMODE,PDO::ERRMODE_EXCEPTION);
        $this->db->setAttribute(PDO::ATTR_EMULATE_PREPARES,false);
        $this->requireUat();
    }

    private function requireUat(): void
    {
        if ($this->db->getAttribute(PDO::ATTR_DRIVER_NAME)!=='mysql'
            || $this->db->query('SELECT DATABASE()')->fetchColumn()!=='v8_test') {
            throw new RetailerSaleError('Employee Cash history restricted to disposable v8_test.');
        }
    }

    public function view(int $company,int $branch,int $actor,int $employee,int $limit=50,int $offset=0):array
    {
        foreach ([$company,$branch,$actor,$employee] as $id) {
            if ($id<=0)throw new RetailerSaleError('Positive trusted Cash history identifiers required.');
        }
        if ($limit<1||$limit>100||$offset<0||$offset>50000)
            throw new RetailerSaleError('Cash history pagination invalid.');
        $this->requireUat();
        if (($this->authorize)('b2b.cash_custody.view',$actor,$company,$branch,$employee)!==true)
            throw new RetailerSaleError('Employee Cash responsibility access denied.');
        // Subquery aggregates journals BEFORE joining them to a sale:
        // remittance never creates a second retail sale or retailer credit.
        $sql="SELECT s.id sale_id,s.posted_at,s.invoice_total_paise,s.actor_id sale_actor_id,
                r.amount_due_paise,r.amount_remitted_paise,r.status custody_status,
                e.id remittance_event_id,e.actor_id cashier_actor_id,e.amount_paise event_amount_paise,e.status event_status,
                v.id verified_receipt_id,a.cashier_actor_id attesting_cashier_id,
                COALESCE(j.journal_count,0) journal_count,
                COALESCE(j.cash_dr,0) cash_dr,COALESCE(j.cash_cr,0) cash_cr,
                COALESCE(j.transit_dr,0) transit_dr,COALESCE(j.transit_cr,0) transit_cr,
                COALESCE(j.unknown_count,0) unknown_count
              FROM v8_b2b_sales s
              LEFT JOIN v8_b2b_employee_remittance r
                ON r.sale_id=s.id AND r.company_id=s.company_id
               AND r.branch_id=s.branch_id AND r.employee_id=s.employee_id
              LEFT JOIN v8_b2b_remittance_events e
                ON e.company_id=s.company_id AND e.branch_id=s.branch_id
               AND e.sale_id=s.id AND e.employee_id=s.employee_id
              LEFT JOIN v8_b2b_verified_branch_receipts v
                ON v.company_id=e.company_id AND v.branch_id=e.branch_id
               AND v.sale_id=e.sale_id AND v.employee_id=e.employee_id
               AND v.cash_receipt_reference=e.cash_receipt_reference
               AND v.amount_paise=e.amount_paise
               AND v.consumed_event_id=e.id
               AND v.status='confirmed' AND v.verified_source='cashier'
              LEFT JOIN v8_b2b_cashier_receipt_attestations a
                ON a.receipt_id=v.id AND a.company_id=v.company_id
               AND a.branch_id=v.branch_id AND a.sale_id=v.sale_id
               AND a.employee_id=v.employee_id AND a.amount_paise=v.amount_paise
               AND a.cash_receipt_reference=v.cash_receipt_reference
               AND a.cashier_actor_id=e.actor_id AND a.cashier_actor_id<>s.actor_id
              LEFT JOIN (
                SELECT event_id,COUNT(*) journal_count,
                   SUM(CASE WHEN account_code='BRANCH_CASH' THEN debit_paise ELSE 0 END) cash_dr,
                   SUM(CASE WHEN account_code='BRANCH_CASH' THEN credit_paise ELSE 0 END) cash_cr,
                   SUM(CASE WHEN account_code='EMPLOYEE_CASH_IN_TRANSIT' THEN debit_paise ELSE 0 END) transit_dr,
                   SUM(CASE WHEN account_code='EMPLOYEE_CASH_IN_TRANSIT' THEN credit_paise ELSE 0 END) transit_cr,
                   SUM(CASE WHEN account_code NOT IN ('BRANCH_CASH','EMPLOYEE_CASH_IN_TRANSIT') THEN 1 ELSE 0 END) unknown_count
                FROM v8_b2b_remittance_journal_lines GROUP BY event_id
              ) j ON j.event_id=e.id
              WHERE s.company_id=? AND s.branch_id=? AND s.employee_id=?
                AND s.channel='field' AND s.payment_mode='cash' AND s.status='paid_posted'
              ORDER BY s.posted_at DESC,s.id DESC LIMIT {$limit} OFFSET {$offset}";
        $stmt=$this->db->prepare($sql);
        $stmt->execute([$company,$branch,$employee]);
        $rows=$stmt->fetchAll(PDO::FETCH_ASSOC);
        $result=[];
        foreach($rows as $row) {
            $due=(int)($row['amount_due_paise']??0);
            $remitted=(int)($row['amount_remitted_paise']??0);
            $event=$row['remittance_event_id']===null?null:(int)$row['remittance_event_id'];
            $pending=$due>0 && $due===(int)$row['invoice_total_paise']
                && $remitted===0 && $row['custody_status']==='pending' && $event===null;
            $balanced=$event!==null && $row['event_status']==='posted'
                && $row['custody_status']==='settled' && $remitted===$due
                && (int)$row['event_amount_paise']===$due
                && $row['verified_receipt_id']!==null
                && $row['attesting_cashier_id']!==null
                && (int)$row['attesting_cashier_id']===(int)$row['cashier_actor_id']
                && (int)$row['journal_count']===2
                && (int)$row['cash_dr']===$due && (int)$row['transit_cr']===$due
                && (int)$row['cash_cr']===0 && (int)$row['transit_dr']===0
                && (int)$row['unknown_count']===0;
            $status=$pending?'employee_cash_pending':($balanced?'cashier_remittance_evidenced':'reconciliation_mismatch');
            $result[]=[
                'sale_id'=>(int)$row['sale_id'],
                'collected_paise'=>(int)$row['invoice_total_paise'],
                'cash_liability_paise'=>$due,
                'remitted_paise'=>$balanced?$remitted:0,
                'status'=>$status,'remittance_event_id'=>$event,
                'independent_cashier_receipt_verified'=>$balanced,
                'canonical_v7_gl_verified'=>false,
                'customer_sale_count'=>1, // remittance only transfers custody, no second sale
            ];
        }
        return ['employee_id'=>$employee,'company_id'=>$company,'branch_id'=>$branch,
            'rows'=>$result,'read_only'=>true,'source'=>'uat_b2b_cash_custody_not_canonical_v7',
            'warning'=>'Verified internal cashier evidence is not proof of canonical V7 GL posting or external bank deposit.'];
    }
}
