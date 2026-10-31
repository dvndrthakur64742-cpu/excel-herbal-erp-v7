<?php
namespace ExcelHerbal\ERP7\Admin;
use ExcelHerbal\ERP7\Database\Db;
final class Dashboard {
 public static function boot():void {add_action('admin_menu',[self::class,'menu']);}
 public static function menu():void {
  add_menu_page('Excel Herbal ERP','Excel Herbal ERP','manage_options','eh7-dashboard',[self::class,'overview'],'dashicons-groups',26);
  add_submenu_page('eh7-dashboard','Employees & Login','Employees & Login','manage_options','eh7-employees',[self::class,'employees']);
  add_submenu_page('eh7-dashboard','ERP API & Status','ERP API & Status','manage_options','eh7-status',[self::class,'status']);
 }
 private static function heading(string $title):void {echo '<div class="wrap"><h1>'.esc_html($title).'</h1>';}
 public static function overview():void {
  self::heading('Excel Herbal ERP — Administration');
  echo '<p>ERP backend is active. Use the links below to manage employee login or check the API. This is the WordPress administration interface, not the Flutter application.</p>';
  echo '<p><a class="button button-primary" href="'.esc_url(admin_url('admin.php?page=eh7-employees')).'">Employees & Login</a> <a class="button" href="'.esc_url(admin_url('admin.php?page=eh7-status')).'">API & Status</a></p></div>';
 }
 public static function status():void {
  self::heading('ERP API & Status');
  echo '<p>Plugin version: <strong>'.esc_html(EH7_VERSION).'</strong></p>';
  foreach(['health','setup/status','app/capabilities'] as $path){$url=rest_url('excel-herbal-erp/v7/'.$path);echo '<p><a href="'.esc_url($url).'" target="_blank" rel="noopener noreferrer">'.esc_html($path).'</a></p>';}
  echo '<p>Employee login requires valid linked WordPress credentials; an employee record alone does not enable login.</p></div>';
 }
 public static function employees():void {
  self::heading('Employees & Login');
  echo '<p>Set login credentials individually after verifying the employee identity. Passwords are not displayed or stored by this page. Do not grant WordPress administrator access to employees.</p>';
  $db=Db::wpdb();$t=Db::table('employees');$users=$db->users;
  $rows=$db->get_results("SELECT e.id,e.employee_code,e.full_name,e.status,e.wp_user_id, u.ID AS valid_user_id FROM {$t} e LEFT JOIN {$users} u ON u.ID=e.wp_user_id ORDER BY e.id ASC LIMIT 500",ARRAY_A);
  if(!is_array($rows)){echo '<div class="notice notice-error"><p>Could not load employees.</p></div></div>';return;}
  $summary=['linked'=>0,'broken'=>0,'unlinked'=>0];
  $activeSummary=['linked'=>0,'broken'=>0,'unlinked'=>0];
  foreach($rows as $row){
   $kind=!empty($row['valid_user_id'])?'linked':(empty($row['wp_user_id'])?'unlinked':'broken');
   $summary[$kind]++;
   if((string)$row['status']==='active')$activeSummary[$kind]++;
  }
  echo '<div class="notice notice-info inline"><p><strong>Login identity audit (read-only):</strong> '.esc_html((string)$summary['linked']).' linked, '.esc_html((string)$summary['broken']).' broken, '.esc_html((string)$summary['unlinked']).' unlinked ('.esc_html((string)count($rows)).' employee records shown).</p>';
  echo '<p><strong>Active employees only:</strong> '.esc_html((string)$activeSummary['linked']).' linked, '.esc_html((string)$activeSummary['broken']).' broken, '.esc_html((string)$activeSummary['unlinked']).' unlinked. This does not verify employee identity or password ownership. Repair individually after verification; there is no bulk password reset.';
  if(count($rows)===500)echo ' Only the first 500 employees are included in this summary.';
  echo '</p></div>';
  echo '<table class="widefat striped"><thead><tr><th>ID</th><th>Employee</th><th>Status</th><th>WordPress link</th><th>Login setup</th></tr></thead><tbody>';
  foreach($rows as $row){$id=(int)$row['id'];$valid=!empty($row['valid_user_id']);$label=$valid?'Linked (user #'.(int)$row['valid_user_id'].')':(empty($row['wp_user_id'])?'Not linked':'Broken link');
    $action=(string)$row['status']==='active'?'<button type="button" class="button eh7-setup" data-id="'.esc_attr((string)$id).'" data-name="'.esc_attr((string)$row['full_name']).'">Set password / Repair link</button>':'<em>Reactivate employee first</em>';
   echo '<tr><td>'.esc_html((string)$id).'</td><td>'.esc_html((string)$row['full_name']).'<br><small>'.esc_html((string)$row['employee_code']).'</small></td><td>'.esc_html((string)$row['status']).'</td><td>'.esc_html($label).'</td><td>'.$action.'</td></tr>';
  }
  echo '</tbody></table><div id="eh7-login-editor" style="display:none;margin-top:22px;padding:18px;background:white;border:1px solid #c3c4c7;max-width:550px"><h2 id="eh7-login-name"></h2><label for="eh7-login-password">New employee password</label><p><input id="eh7-login-password" type="password" autocomplete="new-password" class="regular-text" minlength="12" required></p><button id="eh7-save-login" type="button" class="button button-primary">Save login credentials</button><p id="eh7-login-result" role="status"></p></div>';
  $url=rest_url('excel-herbal-erp/v7/organization/employees/');$nonce=wp_create_nonce('wp_rest');
  echo '<script>(function(){"use strict";let id=0;const box=document.getElementById("eh7-login-editor"),result=document.getElementById("eh7-login-result"),pw=document.getElementById("eh7-login-password"),save=document.getElementById("eh7-save-login");document.querySelectorAll(".eh7-setup").forEach(b=>b.addEventListener("click",()=>{id=Number(b.dataset.id);document.getElementById("eh7-login-name").textContent="Login setup: "+b.dataset.name;pw.value="";result.textContent="";box.style.display="block";box.scrollIntoView({behavior:"smooth",block:"nearest"});}));save.addEventListener("click",async()=>{if(!id||pw.value.length<12){result.textContent="Use a password of at least 12 characters.";return;}if(!confirm("Create or update login credentials for this employee?"))return;save.disabled=true;result.textContent="Saving…";try{const response=await fetch('.wp_json_encode($url).'+id+"/login-credentials",{method:"POST",credentials:"same-origin",headers:{"Content-Type":"application/json","X-WP-Nonce":'.wp_json_encode($nonce).', "X-Idempotency-Key":crypto.randomUUID()},body:JSON.stringify({password:pw.value})});const data=await response.json();result.textContent=response.ok?"Credentials saved. Reload to confirm WordPress link.":"Error: "+(data.error?.message||data.message||JSON.stringify(data));if(response.ok)pw.value="";}catch(e){result.textContent="Network error: "+e.message;}finally{save.disabled=false;}});})();</script></div>';
 }
}
