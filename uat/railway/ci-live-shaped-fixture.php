<?php
/** Live-shaped schema, dummy data ONLY, disposable GitHub CI database. */
declare(strict_types=1);
function eh7_ci_live_shaped_fixture(): array {
    global $wpdb;
    if (getenv('EH7_CI_ISOLATED') !== '1' ||
        wp_get_environment_type() !== 'staging' ||
        (string) $wpdb->dbname !== 'eh7_ci_synthetic' ||
        !str_starts_with((string)$wpdb->dbhost, 'eh7-ci-mariadb-')) {
        throw new \RuntimeException('ONLY disposable CI MariaDB is eligible for live-shaped fixture');
    }
    $p = $wpdb->prefix . 'eh7_';
    $schemas = [
        'report_reminder_drafts' => "(
         id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
         company_id BIGINT UNSIGNED NOT NULL, branch_id BIGINT UNSIGNED NOT NULL,
         report_type VARCHAR(40) NOT NULL, period_date DATE NOT NULL,
         target_employee_id BIGINT UNSIGNED NOT NULL, reason VARCHAR(40) NOT NULL,
         state VARCHAR(20) NOT NULL, dedupe_key CHAR(64) NOT NULL,
         created_by BIGINT UNSIGNED NOT NULL, created_at DATETIME NOT NULL,
         dismissed_at DATETIME NULL, dismissed_by BIGINT UNSIGNED NULL,
         dismissal_reason VARCHAR(500) NULL, PRIMARY KEY(id),
         UNIQUE KEY uniq_draft_key (dedupe_key),
         KEY branch_drafts (company_id,branch_id,period_date,state)) ENGINE=InnoDB",
        'report_submissions' => "(
         id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
         company_id BIGINT UNSIGNED NOT NULL, branch_id BIGINT UNSIGNED NOT NULL,
         report_type VARCHAR(40) NOT NULL, period_date DATE NOT NULL,
         summary_text TEXT NOT NULL, content_sha256 CHAR(64) NOT NULL,
         status VARCHAR(20) NOT NULL, revision INT NOT NULL,
         submitted_by BIGINT UNSIGNED NOT NULL, submitted_at DATETIME NOT NULL,
         reviewed_by BIGINT UNSIGNED NULL, reviewed_at DATETIME NULL,
         review_note VARCHAR(500) NULL, created_at DATETIME NOT NULL,
         PRIMARY KEY(id), UNIQUE KEY uniq_report (company_id,branch_id,report_type,period_date),
         KEY scope_status (company_id,branch_id,status,period_date)) ENGINE=InnoDB",
        'report_submission_events' => "(
         id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
         company_id BIGINT UNSIGNED NOT NULL, branch_id BIGINT UNSIGNED NOT NULL,
         submission_id BIGINT UNSIGNED NOT NULL, revision INT NOT NULL,
         event_type VARCHAR(20) NOT NULL, actor_employee_id BIGINT UNSIGNED NOT NULL,
         content_sha256 CHAR(64) NOT NULL, content_snapshot TEXT NOT NULL,
         note VARCHAR(500) NOT NULL, created_at DATETIME NOT NULL,
         PRIMARY KEY(id), UNIQUE KEY one_event (submission_id,revision,event_type),
         KEY report_event (company_id,branch_id,submission_id,id)) ENGINE=InnoDB",
    ];
    $sessions = $p . 'mobile_sessions';
    $employees = $p . 'employees';
    $quarantine = $p . 'stock_quarantine';
    $fieldId = (int) $wpdb->get_var("SELECT id FROM {$employees} WHERE employee_code='UAT-FIELD' AND status='active' LIMIT 1");
    if ($fieldId < 1 || (int)$wpdb->get_var("SELECT COUNT(*) FROM {$sessions}") !== 0 ||
        (int)$wpdb->get_var("SELECT COUNT(*) FROM {$quarantine}") !== 0) {
        throw new \RuntimeException('Nonempty sessions or quarantine, or missing CI synthetic staff');
    }
    foreach ($schemas as $name => $_ddl) {
        if ((string)$wpdb->get_var($wpdb->prepare('SHOW TABLES LIKE %s', $p.$name)) === $p.$name) {
            throw new \RuntimeException('Refuse existing report table ' . $name);
        }
    }
    $existingIndex = (array)$wpdb->get_col("SHOW INDEX FROM {$sessions} WHERE Key_name='employee_device'", 2);
    $existingEmployeeExtra = (array)$wpdb->get_col("SHOW INDEX FROM {$employees} WHERE Key_name='branch_status'", 2);
    $stockExtra = (int)$wpdb->get_var("SELECT COUNT(*) FROM information_schema.COLUMNS " .
        "WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='{$quarantine}' AND " .
        "COLUMN_NAME IN ('unit_cost_snapshot','journal_entry_id')");
    if (count($existingIndex) !== 3 || count($existingEmployeeExtra) !== 0 || $stockExtra !== 0) {
        throw new \RuntimeException('Unexpected initial source schema, do not alter');
    }
    foreach ($schemas as $name => $ddl) {
        if ($wpdb->query("CREATE TABLE {$p}{$name} {$ddl}") === false) {
            throw new \RuntimeException('Creating synthetic report table failed: ' . $name);
        }
    }
    if ($wpdb->query("ALTER TABLE {$quarantine} " .
        "ADD COLUMN unit_cost_snapshot DECIMAL(14,4) NOT NULL DEFAULT 0.0000 AFTER quantity, " .
        "ADD COLUMN journal_entry_id BIGINT UNSIGNED NULL AFTER resolved_by") === false ||
        $wpdb->query("ALTER TABLE {$employees} ADD KEY branch_status (company_id,assigned_branch_id,status)") === false ||
        $wpdb->query("ALTER TABLE {$sessions} DROP INDEX employee_device") === false) {
        throw new \RuntimeException('Disposable live-schema differences could not be recreated');
    }

    $now=gmdate('Y-m-d H:i:s');$date=gmdate('Y-m-d');
    $hash=hash('sha256','CI synthetic test report');
    if (!$wpdb->insert($p.'report_reminder_drafts',[
        'company_id'=>1,'branch_id'=>1,'report_type'=>'CI_TEST',
        'period_date'=>$date,'target_employee_id'=>$fieldId,
        'reason'=>'ci_fixture','state'=>'draft',
        'dedupe_key'=>hash('sha256','CI DRAFT'),'created_by'=>$fieldId,'created_at'=>$now
    ]))throw new \RuntimeException('Synthetic reminder insertion failed');
    if (!$wpdb->insert($p.'report_submissions',[
        'company_id'=>1,'branch_id'=>1,'report_type'=>'CI_TEST',
        'period_date'=>$date,'summary_text'=>'Dummy test report',
        'content_sha256'=>$hash,'status'=>'submitted','revision'=>1,
        'submitted_by'=>$fieldId,'submitted_at'=>$now,'created_at'=>$now
    ]))throw new \RuntimeException('Synthetic report submission failed');
    $submissionId=(int)$wpdb->insert_id;
    if (!$wpdb->insert($p.'report_submission_events',[
        'company_id'=>1,'branch_id'=>1,'submission_id'=>$submissionId,
        'revision'=>1,'event_type'=>'submitted','actor_employee_id'=>$fieldId,
        'content_sha256'=>$hash,'content_snapshot'=>'Dummy test report',
        'note'=>'Dummy migration fixture','created_at'=>$now
    ]))throw new \RuntimeException('Synthetic report event insertion failed');
    if (!$wpdb->insert($quarantine,[
        'company_id'=>1,'branch_id'=>1,'product_id'=>1,'batch_id'=>null,
        'quantity'=>'0.250','unit_cost_snapshot'=>'12.3400',
        'reason'=>'CI dummy quarantine','status'=>'open','created_by'=>$fieldId,
        'journal_entry_id'=>null,'created_at'=>$now
    ]))throw new \RuntimeException('Synthetic quarantine insertion failed');
    return array_map(static fn(string $name):string => $p.$name, array_keys($schemas));
}
