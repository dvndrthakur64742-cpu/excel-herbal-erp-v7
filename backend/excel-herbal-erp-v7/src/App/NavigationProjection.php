<?php
namespace ExcelHerbal\ERP7\App;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Capabilities;
final class NavigationProjection {
 public static function make(Actor $a):array {
  $can=fn(array $caps)=>(bool)array_intersect($caps,$a->capabilities);
  $sections=[
   ['id'=>'home','label'=>'Home','visible'=>true],
   ['id'=>'my_work','label'=>'My Work','visible'=>$can([Capabilities::ATT_SELF,Capabilities::LEAVE_SELF,Capabilities::FIELD_SELF,Capabilities::DAILY_SELF])],
   ['id'=>'team','label'=>'Team Operations','visible'=>$can([Capabilities::EMP_VIEW,Capabilities::ATT_MANAGE,Capabilities::LEAVE_MANAGE,Capabilities::DAILY_OTHERS,Capabilities::DAILY_APPROVE,Capabilities::DAILY_ISSUE,Capabilities::DAILY_REVIEW])],
   ['id'=>'sales','label'=>'Sales & Collections','visible'=>$can([Capabilities::SALES_VIEW,Capabilities::SALES_CREATE,Capabilities::RECEIPT_CREATE])],
   ['id'=>'inventory','label'=>'Inventory','visible'=>$can([Capabilities::INVENTORY_VIEW,Capabilities::TRANSFER_CREATE,Capabilities::TRANSFER_RECEIVE,Capabilities::TRANSFER_CANCEL,Capabilities::ADJ_CREATE,Capabilities::ADJ_APPROVE])],
   ['id'=>'purchase','label'=>'Purchase & Suppliers','visible'=>$can([Capabilities::PURCHASE_VIEW,Capabilities::PURCHASE_CREATE,Capabilities::SUPPLIER_PAYMENT])],
   ['id'=>'finance','label'=>'Finance & Accounts','visible'=>$can([Capabilities::FINANCE_VIEW,Capabilities::ACCOUNTING_VIEW,Capabilities::ACCOUNT_MANAGE,Capabilities::EXPENSE_CREATE,Capabilities::EXPENSE_APPROVE,Capabilities::BRANCH_CLOSE,Capabilities::BRANCH_REOPEN,Capabilities::REVERSAL_CREATE,Capabilities::REVERSAL_APPROVE,Capabilities::PERIOD_MANAGE,Capabilities::BANK_RECONCILE])],
   ['id'=>'payroll_performance','label'=>'Payroll & Performance','visible'=>$can([Capabilities::PAYROLL_GENERATE,Capabilities::PAYROLL_APPROVE,Capabilities::PAYROLL_PAY,Capabilities::PERFORMANCE_VIEW,Capabilities::PERFORMANCE_MANAGE])],
   ['id'=>'reports','label'=>'Reports Centre','visible'=>$can([Capabilities::REPORTS_VIEW,Capabilities::ACCOUNTING_VIEW])],
   ['id'=>'organization','label'=>'Organization & Masters','visible'=>$can([Capabilities::EMP_VIEW,Capabilities::EMP_MANAGE,Capabilities::HR_VIEW,Capabilities::HR_MANAGE,Capabilities::HR_REVIEW,Capabilities::BRANCH_VIEW,Capabilities::BRANCH_MANAGE,Capabilities::PRODUCT_VIEW,Capabilities::PRODUCT_MANAGE])],
   ['id'=>'communication','label'=>'Communication','visible'=>$can([Capabilities::COMM_VIEW,Capabilities::COMM_MANAGE])],
   ['id'=>'administration','label'=>'Administration','visible'=>$can([Capabilities::AUDIT_VIEW,Capabilities::ACCESS_MANAGE,Capabilities::REVERSAL_CREATE,Capabilities::REVERSAL_APPROVE,Capabilities::PERIOD_MANAGE])],
  ];
  $bottom=[['id'=>'home','label'=>'Home']];
  if($can([Capabilities::ATT_SELF,Capabilities::LEAVE_SELF,Capabilities::FIELD_SELF,Capabilities::DAILY_SELF]))$bottom[]=['id'=>'my_work','label'=>'My Work'];
  if($can([Capabilities::DAILY_SELF,Capabilities::DAILY_OTHERS,Capabilities::SALES_CREATE,Capabilities::RECEIPT_CREATE,Capabilities::TRANSFER_CREATE,Capabilities::ADJ_CREATE,Capabilities::PURCHASE_CREATE,Capabilities::EXPENSE_CREATE]))$bottom[]=['id'=>'actions','label'=>'Actions'];
  if($can([Capabilities::COMM_VIEW]))$bottom[]=['id'=>'tasks','label'=>'Tasks'];
  $bottom[]=['id'=>'profile','label'=>'Profile'];
  return ['sections'=>array_values(array_filter($sections,fn($x)=>$x['visible'])),'bottom_nav'=>$bottom];
 }
}
