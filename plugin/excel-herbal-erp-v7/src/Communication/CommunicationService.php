<?php
namespace ExcelHerbal\ERP7\Communication;

use ExcelHerbal\ERP7\Database\Db;
use ExcelHerbal\ERP7\Database\Transaction;
use ExcelHerbal\ERP7\Domain\DomainException;
use ExcelHerbal\ERP7\Security\Actor;
use ExcelHerbal\ERP7\Security\Capabilities;
use ExcelHerbal\ERP7\Security\Guard;

final class CommunicationService {
    private static function rows($db,string $sql,array $args):array {
        $rows=$db->get_results($db->prepare($sql,...$args),ARRAY_A);
        if (($db->last_error??'')!=='' || !is_array($rows)) {
            throw new DomainException('Inbox could not be loaded. Retry shortly.','communication_unavailable',503);
        }
        return $rows;
    }

    /** Read-only deadline projection; no scheduled message or delivery side effect. */
    public static function deadlineState(?string $due,string $now):string {
        if ($due===null || $due==='') return 'no_due';
        $zone=new \DateTimeZone('UTC');
        foreach ([$due,$now] as $stamp) {
            $parsed=\DateTimeImmutable::createFromFormat('!Y-m-d H:i:s',$stamp,$zone);
            if (!$parsed || $parsed->format('Y-m-d H:i:s')!==$stamp) return 'unverified';
        }
        return $due<=$now?'overdue':'upcoming';
    }

    public static function summary(Actor $a):array {
        Guard::cap($a,Capabilities::COMM_VIEW);
        $db=Db::wpdb();
        $now=Db::now();
        $ids=$a->branchIds?implode(',',array_map('intval',$a->branchIds)):'0';
        $tasks=self::rows($db,"SELECT * FROM ".Db::table('tasks')." WHERE company_id=%d AND assigned_employee_id=%d AND status='open' ORDER BY due_at IS NULL,due_at,id DESC LIMIT 100",[$a->companyId,$a->employeeId]);
        foreach ($tasks as &$task) $task['deadline_state']=self::deadlineState($task['due_at']??null,$now);
        unset($task);
        return [
            'tasks'=>$tasks,
            'announcements'=>self::rows($db,"SELECT * FROM ".Db::table('announcements')." WHERE company_id=%d AND status='published' AND (branch_id IS NULL OR branch_id IN ({$ids})) AND (expires_at IS NULL OR expires_at>%s) ORDER BY published_at DESC LIMIT 50",[$a->companyId,$now]),
            'notifications'=>self::rows($db,"SELECT * FROM ".Db::table('notifications')." WHERE company_id=%d AND employee_id=%d ORDER BY created_at DESC LIMIT 100",[$a->companyId,$a->employeeId]),
        ];
    }

    public static function completeTask(Actor $a,int $id):array {
        Guard::cap($a,Capabilities::COMM_VIEW);
        return Transaction::run(function()use($a,$id){
            $db=Db::wpdb();$t=Db::table('tasks');
            $r=$db->get_row($db->prepare("SELECT * FROM {$t} WHERE id=%d AND company_id=%d AND assigned_employee_id=%d FOR UPDATE",$id,$a->companyId,$a->employeeId),ARRAY_A);
            if (($db->last_error??'')!=='') throw new DomainException('Task unavailable.','communication_unavailable',503);
            if (!$r) throw new DomainException('Task not found.','task_not_found',404);
            if ($r['status']==='completed') return ['id'=>$id,'status'=>'completed'];
            if ($r['status']!=='open') throw new DomainException('Only an open task can be completed.','task_state_invalid',409);
            $updated=Db::mustUpdate($db,$t,['status'=>'completed','completed_at'=>Db::now()],
                ['id'=>$id,'company_id'=>$a->companyId,'assigned_employee_id'=>$a->employeeId,'status'=>'open']);
            if ($updated!==1) throw new DomainException('Task changed. Refresh your inbox.','task_state_invalid',409);
            return ['id'=>$id,'status'=>'completed'];
        });
    }
}
