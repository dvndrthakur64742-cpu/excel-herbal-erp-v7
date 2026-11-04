<?php
/** Historic Office V7 extra nonunique lookup indexes. Metadata only.
 * Use ONLY in disposable, synthetic WordPress/MariaDB CI fixtures.
 */
declare(strict_types=1);
function eh7_ci_live_only_index_map(): array {
    return [
        'employees' => [
            'branch_status'=>['company_id','assigned_branch_id','status']
        ],
        'stock_transfers' => [
            'destination_status'=>['company_id','destination_branch_id','status','id'],
            'source_status'=>['company_id','source_branch_id','status','id']
        ],
        'stock_adjustments' => [
            'branch_status'=>['company_id','branch_id','status','id']
        ],
        'parties' => [
            'branch_type_status'=>['company_id','branch_id','type','status']
        ],
        'counter_sales' => [
            'branch_date'=>['company_id','branch_id','sale_date','id'],
            'branch_status_outstanding'=>['company_id','branch_id','status','outstanding_amount']
        ],
        'suppliers' => [
            'company_status'=>['company_id','status']
        ],
        'purchase_bills' => [
            'branch_status_outstanding'=>['company_id','branch_id','status','outstanding_amount','bill_date','id']
        ],
        'journal_entries' => [
            'company_source'=>['company_id','source_type','source_id','status'],
            'company_status_date'=>['company_id','status','entry_date','id']
        ],
        'leave_requests' => [
            'branch_status'=>['company_id','branch_id','status']
        ],
        'holidays' => [
            'scope_date'=>['company_id','branch_id','holiday_date','active']
        ],
        'tasks' => [
            'employee_status_due'=>['company_id','assigned_employee_id','status','due_at','id']
        ],
        'announcements' => [
            'company_status_published'=>['company_id','status','published_at','id']
        ],
        'notifications' => [
            'employee_created'=>['company_id','employee_id','created_at','id']
        ]
    ];
}
