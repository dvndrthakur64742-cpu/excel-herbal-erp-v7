<?php
namespace ExcelHerbal\ERP7\Http;
use ExcelHerbal\ERP7\Reporting\B2BStagingRestProbe;use ExcelHerbal\ERP7\Payroll\SalaryService;use ExcelHerbal\ERP7\App\NavigationProjection;use ExcelHerbal\ERP7\Database\Db;use ExcelHerbal\ERP7\Database\Schema;use ExcelHerbal\ERP7\Domain\DomainException;use ExcelHerbal\ERP7\Policy\BusinessPolicy;use ExcelHerbal\ERP7\Security\Actor;use ExcelHerbal\ERP7\Security\ActorResolver;use ExcelHerbal\ERP7\Security\AccessService;use ExcelHerbal\ERP7\Security\Capabilities;use ExcelHerbal\ERP7\Security\Guard;use ExcelHerbal\ERP7\Security\Idempotency;use ExcelHerbal\ERP7\Security\MobileAuth;use ExcelHerbal\ERP7\Security\SessionService;use ExcelHerbal\ERP7\Security\HierarchyScope;use ExcelHerbal\ERP7\Organization\OrganizationService;use ExcelHerbal\ERP7\Organization\DocumentService;use ExcelHerbal\ERP7\Organization\HrLifecycleService;use ExcelHerbal\ERP7\Workforce\WorkforceService;use ExcelHerbal\ERP7\Workforce\HolidayService;use ExcelHerbal\ERP7\DailyOrder\DailyOrderService;use ExcelHerbal\ERP7\Inventory\InventoryService;use ExcelHerbal\ERP7\Sales\SalesService;use ExcelHerbal\ERP7\Purchase\PurchaseService;use ExcelHerbal\ERP7\Finance\FinanceService;use ExcelHerbal\ERP7\Payroll\PayrollPerformanceService;use ExcelHerbal\ERP7\Reporting\ReportingService;use ExcelHerbal\ERP7\Communication\CommunicationService;use ExcelHerbal\ERP7\Communication\CommunicationAdminService;use ExcelHerbal\ERP7\Setup\SetupService;use ExcelHerbal\ERP7\Recovery\RecoveryService;use ExcelHerbal\ERP7\Recovery\WholePcsGuard;use ExcelHerbal\ERP7\Administration\MaintenanceService;use ExcelHerbal\ERP7\Administration\ActingDutyService;
final class Api{
 private static function dispatch(string $h,$r,?Actor $a):mixed{return ApiDispatch::dispatch($h,$r,$a);}

 private const NS='excel-herbal-erp/v7';
 public static function register():void{
  foreach(RouteRegistry::routes() as[$method,$path,$handler,$auth]){
   // Never register the UAT staging probe on a production database or WP host.
   if($handler==='dev.b2b_probe'&&!B2BStagingRestProbe::exposable())continue;
   register_rest_route(self::NS,$path,['methods'=>$method,'permission_callback'=>'__return_true',
      'callback'=>fn($r)=>self::respond($r,$handler,$auth,$method)]);
  }
 }
 private static function respond($r,string $handler,bool $auth,string $method):\WP_REST_Response{
  $requestId=substr(str_replace('-','',wp_generate_uuid4()),0,24);
  try{
   ApiContract::validate($handler,$r,$method);
   $actor=$auth?ActorResolver::current():null;
   if($auth&&$actor&&!$actor->branchIds&&!in_array($handler,['bootstrap','me'],true)&&!str_starts_with($handler,'auth.'))throw new DomainException('No authorised business branch is assigned.','branch_access_required',403);
   if($method!=='GET'){try{WholePcsGuard::validatePayload(self::arrBody($r));}catch(\InvalidArgumentException $e){throw new DomainException($e->getMessage(),'whole_pcs_required',422);}}
   $run=fn()=>self::dispatch($handler,$r,$actor);
   $idempotencyKey=(string)$r->get_header('X-Idempotency-Key');if($idempotencyKey===''&&in_array($handler,['admin.transfer_accounting_repair','admin.cleanup'],true))$idempotencyKey=trim((string)$r->get_param('idempotency_key'));
   $data=($auth&&$method!=='GET'&&!str_starts_with($handler,'auth.'))?Idempotency::run($actor,$idempotencyKey,$handler,$run,self::idempotencyPayload($r,$handler)):$run();
   if(in_array($handler,['org.document_download','hr.document_download'],true)){
    $response=new \WP_REST_Response($data['bytes'],200);$response->header('Content-Type',$data['mime_type']);$response->header('Content-Disposition',"attachment; filename*=UTF-8''".rawurlencode($data['filename']));$response->header('Cache-Control','private, no-store');$response->header('X-Content-Type-Options','nosniff');$response->header('X-EH7-Private-Document','1');return $response;
   }
   return self::response(['ok'=>true,'data'=>$data],200,$requestId);
  }catch(DomainException $e){return self::response(['ok'=>false,'error'=>['code'=>$e->codeKey,'message'=>$e->getMessage()],'request_id'=>$requestId],$e->httpStatus,$requestId);}
  catch(\Throwable $e){if(defined('WP_DEBUG')&&WP_DEBUG)error_log('EH7 request '.$requestId.' '.$e->getMessage());return self::response(['ok'=>false,'error'=>['code'=>'internal_error','message'=>'Unexpected ERP error.'],'request_id'=>$requestId],500,$requestId);}
 }
 private static function response(array $body,int $status,string $requestId):\WP_REST_Response{$response=new \WP_REST_Response($body,$status);$response->header('X-EH7-Version',EH7_VERSION);$response->header('X-EH7-Contract',ApiContract::VERSION);$response->header('X-Request-Id',$requestId);return $response;}
       private static function idempotencyPayload($r,string $handler):array{$payload=(array)$r->get_params();if(in_array($handler,['org.employee_document_upload','hr.candidate_document_upload'],true)&&!empty($_FILES['file'])&&is_array($_FILES['file'])){$f=$_FILES['file'];$payload['_file_name']=(string)($f['name']??'');$payload['_file_size']=(int)($f['size']??0);$tmp=(string)($f['tmp_name']??'');if($tmp!==''&&is_file($tmp))$payload['_file_sha256']=hash_file('sha256',$tmp)?:'';}return$payload;}
 private static function arrBody($r):array{$v=$r->get_json_params();return is_array($v)?$v:[];}}
