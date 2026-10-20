#!/usr/bin/env python3
"""Real WordPress + actual V7 MobileAuth, ActorResolver, branch Guard over HTTP.

Runs only against locally installed WordPress on disposable v8_test.
Never accepts a host URL, port forwarded to the public Internet, or a live DB.
"""
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request

ROOT=Path(os.environ["B2B_REAL_WP_ROOT"]).resolve()
ROUTER=Path(__file__).with_name("b2b_real_wordpress_router.php").resolve()
PASSWORD=os.environ["B2B_REAL_WP_UAT_PASSWORD"]
assert ROOT.is_dir() and (ROOT/"wp-load.php").exists()
assert len(PASSWORD)>=16
CHECKS=0
ISSUED_REFRESH={}

def ok(condition,label):
    global CHECKS
    if not condition:
        raise AssertionError(label)
    CHECKS+=1
    print("PASS real WordPress:",label,flush=True)

def req(url,path,token=None,body=None,method="GET"):
    headers={"Accept":"application/json"}
    if token:
        headers["Authorization"]="Bearer "+token
    data=None
    if body is not None:
        headers["Content-Type"]="application/json"
        data=json.dumps(body).encode("utf-8")
    r=urllib.request.Request(url+path,data=data,headers=headers,method=method)
    try:
        with urllib.request.urlopen(r,timeout=10) as response:
            return response.status,json.loads(response.read(40000)),response.headers
    except urllib.error.HTTPError as exc:
        b=exc.read(40000)
        try: parsed=json.loads(b)
        except json.JSONDecodeError: parsed={"raw_status":exc.code}
        return exc.code,parsed,exc.headers

def port():
    with socket.socket() as s:
        s.bind(("127.0.0.1",0))
        return s.getsockname()[1]

def expect(url,path,code,error=None,token=None,body=None,method="GET"):
    status,reply,headers=req(url,path,token,body,method)
    actual=reply.get("error",{}).get("code") if isinstance(reply.get("error"),dict) else None
    if status!=code or (error is not None and actual!=error):
        raise AssertionError(
          "HTTP contract expected status="+str(code)+" error="+str(error)+
          " observed="+str(status)+" error="+str(actual)+" response="+
          json.dumps(reply,default=str)[:340]
        )
    return reply,headers

def login(url,mobile):
    reply,_=expect(url,"/auth/login",200,body={
        "mobile":mobile,"password":PASSWORD,"device":"real-wordpress-disposable-ci",
        "device_id":"synthetic-ci-"+mobile
    },method="POST")
    token=reply.get("data",{}).get("access_token")
    refresh=reply.get("data",{}).get("refresh_token")
    ok(isinstance(token,str) and len(token)>30
       and isinstance(refresh,str) and len(refresh)>30,
       "real WordPress password verification and canonical MobileAuth tokens for "+mobile[-2:])
    ISSUED_REFRESH[mobile]=refresh
    return token

def guarded_mutation(action):
    """Change only isolated synthetic WP records through real wpdb/wp-cli.

    The PHP mutation script checks GITHUB_ACTIONS, its installed root,
    development environment, v8_test and exact fixture identity/counts.
    """
    allowed = {
        "deny_finance", "restore_finance",
        "disable_branch", "restore_branch",
        "disable_employee", "restore_employee",
        "hide_payment_table", "restore_payment_table",
        "reactivate_employee_service",
    }
    if action not in allowed:
        raise ValueError("Unknown guarded CI mutation")
    env = dict(os.environ)
    env["B2B_REAL_WP_MUTATION"] = action
    script = Path(__file__).with_name("b2b_real_wp_security_mutation.php").resolve()
    if not script.is_file():
        raise RuntimeError("Real WordPress security mutation script is missing")
    done = subprocess.run(
        ["wp", "eval-file", str(script), "--path=" + str(ROOT)],
        env=env, cwd=str(ROOT), capture_output=True, text=True, timeout=30,
        check=False,
    )
    if done.returncode != 0:
        # Never echo secrets, bearer tokens or arbitrary generated WP-CLI logs.
        # The command receives no bearer token or password argument.
        # Report only an allowlisted diagnostic, never raw WP-CLI output
        # (which might include paths, credentials or request headers).
        hints = ("Refused:", "Synthetic", "fixture", "schema", "payment table",
                 "WP-CLI", "WordPress", "Fatal error", "RuntimeException")
        lines = [line.strip() for line in (done.stderr + "\n" + done.stdout).splitlines()]
        reason = next((line for line in lines if any(h in line for h in hints)), "")
        reason = reason.replace(PASSWORD, "[redacted]")[:180]
        if " in /" in reason:
            reason = reason.split(" in /", 1)[0]
        raise RuntimeError(
            "Guarded disposable wp-cli mutation failed: " + action
            + " exit=" + str(done.returncode)
            + (" reason=" + reason if reason else " reason=unclassified")
        )


def run(url):
    status,body,_=req(url,"/health")
    ok(status==200 and body.get("ok") is True,
       "actual WordPress loaded V7 ERP plugin health endpoint")
    status,body,_=req(url,"/development/b2b-staging-readiness?branch_id=31")
    ok(status==401 and body.get("error",{}).get("code")=="not_authenticated",
       "anonymous request rejected by actual V7 WordPress ActorResolver")
    status,body,_=req(url,"/development/b2b-staging-readiness?branch_id=31",
                     token="invalid-synthetic-token")
    ok(status==401 and body.get("error",{}).get("code")=="not_authenticated",
       "invalid bearer rejected through actual V7 MobileAuth")

    tokens=[]
    try:
        finance=login(url,"9876500101");tokens.append(finance)
        bm=login(url,"9876500102");tokens.append(bm)
        fse=login(url,"9876500103");tokens.append(fse)
        other=login(url,"9876500104");tokens.append(other)
        p="/development/b2b-staging-readiness?branch_id=31"
        result,headers=expect(url,p,200,token=finance)
        data=result["data"]
        ok(data.get("read_only") is True
           and data.get("structural_preflight_possible") is True
           and data.get("existing_source_table_count")==14
           and data.get("all_sources_innodb") is True,
           "real MySQL information_schema confirms all fourteen required InnoDB sources")
        ok(data.get("company_id")==11 and data.get("branch_id")==31
           and data.get("scope")=="authenticated_accounting_actor_authorized_branch",
           "real WordPress user maps to correct canonical ERP employee and branch")
        ok(data.get("financial_posting_enabled") is False
           and data.get("financial_records_disclosed") is False
           and data.get("production_release_authorized") is False
           and data.get("bank_payment_provider_integrated") is False
           and data.get("snapshot_executed") is False,
           "real WordPress HTTP endpoint discloses no finance values and enables no posting")
        ok(bool(headers.get("X-Request-Id")) and bool(headers.get("X-EH7-Version")),
           "canonical response headers propagate through real WordPress REST server")
        for name,token in [("Branch Manager",bm),("FSE",fse)]:
            result,_=expect(url,p,403,"permission_denied",token=token)
            ok(result["ok"] is False,name+" forbidden despite real valid user login")
        expect(url,p,403,"branch_forbidden",token=other)
        ok(True,"different assigned branch forbidden from viewing branch 31")
        expect(url,"/development/b2b-staging-readiness?branch_id=32",
               403,"branch_forbidden",token=finance)
        ok(True,"finance role cannot access unassigned branch")
        expect(url,"/development/b2b-staging-readiness?branch_id=INVALID",
               422,"parameter_invalid",token=finance)
        ok(True,"actual WordPress REST invalid branch fails canonical API validation")
        expect(url,"/development/b2b-staging-readiness",
               422,"parameter_required",token=finance)
        ok(True,"missing mandatory branch fails canonical API validation")
        status,body,_=req(url,p,token=finance,method="POST")
        ok(status in (404,405) and body.get("ok") is not True,
           "WordPress does not register financial B2B staging POST")
        # Remove one UAT-only staging payment-intent table while WordPress
        # is running. The REAL metadata query must remain fail-closed and
        # not silently return a ready signal for a partial migration.
        guarded_mutation("hide_payment_table")
        try:
            incomplete,_=expect(url,p,200,token=finance)
            diag=incomplete.get("data",{})
            ok(diag.get("missing_source_table_count")==1
               and diag.get("structural_preflight_possible") is False
               and diag.get("reason")=="incomplete_disposable_uat_schema"
               and diag.get("production_release_authorized") is False,
               "real MariaDB missing payment-intent table blocks WordPress staging readiness")
        finally:
            guarded_mutation("restore_payment_table")
        repaired,_=expect(url,p,200,token=finance)
        ok(repaired.get("data",{}).get("existing_source_table_count")==14
           and repaired.get("data",{}).get("structural_preflight_possible") is True,
           "real MariaDB staging schema restored and checked without financial posting")

        # Reuse the SAME real WordPress-issued bearer token after a
        # permission change. The actor must be rebuilt on each request
        # rather than caching finance/accounting capability at login.
        guarded_mutation("deny_finance")
        try:
            expect(url,p,403,"permission_denied",token=finance)
            ok(True,"live role override revokes finance view from an already minted bearer")
        finally:
            guarded_mutation("restore_finance")
        restored,_=expect(url,p,200,token=finance)
        ok(restored.get("data",{}).get("structural_preflight_possible") is True,
           "restored finance capability is applied without a new login")

        # When the assigned branch is disabled, every guarded finance
        # request must lose effective branch authority immediately.
        guarded_mutation("disable_branch")
        try:
            expect(url,p,403,"branch_access_required",token=finance)
            ok(True,"inactive branch invalidates effective branch authority on existing bearer")
        finally:
            guarded_mutation("restore_branch")
        restored,_=expect(url,p,200,token=finance)
        ok(restored.get("data",{}).get("branch_id")==31,
           "re-enabled synthetic branch recovers authorized finance scope")

        # Session authentication joins the actual ACTIVE employee row.
        # An employee made inactive must not continue using an old token.
        guarded_mutation("disable_employee")
        try:
            expect(url,p,401,"not_authenticated",token=finance)
            ok(True,"inactive ERP employee denies already issued WordPress bearer token")
        finally:
            guarded_mutation("restore_employee")
        # The synthetic fixture is now back to its original state. Any
        # irreversible session-revocation business policy needs explicit
        # approval and is outside the test helper's direct SQL scope.
        restored,_=expect(url,p,200,token=finance)
        ok(restored.get("data",{}).get("read_only") is True,
           "synthetic employee fixture restored for the normal logout test")

        # A real protected service operation now moves a synthetic employee
        # from inactive -> active, and must revoke all older issued tokens.
        # The earlier direct SQL restoration test proves only temporary
        # inactivation; THIS test proves canonical reactivation rotation.
        old_finance=finance
        old_refresh=ISSUED_REFRESH["9876500101"]
        guarded_mutation("disable_employee")
        try:
            expect(url,p,401,"not_authenticated",token=old_finance)
            guarded_mutation("reactivate_employee_service")
        except Exception:
            # Only use this direct restoration on a failed fixture setup.
            # Never leave a synthetic employee disabled after CI failures.
            try:
                guarded_mutation("restore_employee")
            except Exception:
                pass
            raise
        expect(url,p,401,"not_authenticated",token=old_finance)
        ok(True,"canonical employee reactivation permanently denies old access token")
        expect(url,"/auth/refresh",401,"refresh_invalid",body={
            "refresh_token":old_refresh,
            "device":"real-wordpress-disposable-ci",
            "device_id":"synthetic-ci-9876500101"
        },method="POST")
        ok(True,"canonical reactivation invalidates the actual previously issued refresh token")
        # New authentication is mandatory; no old access token is reused.
        finance=login(url,"9876500101")
        tokens.append(finance)
        result,_=expect(url,p,200,token=finance)
        ok(result.get("data",{}).get("read_only") is True,
           "fresh login after reactivation restores only authorized read access")

        expect(url,"/auth/logout",200,token=finance,method="POST")
        ok(True,"canonical logout revokes real WordPress bearer session")
        status,reply,_=req(url,p,token=finance)
        ok(status==401 and reply.get("error",{}).get("code")=="not_authenticated",
           "revoked mobile bearer immediately denied by actual WordPress")
        tokens.remove(finance)
    finally:
        for token in tokens:
            try:req(url,"/auth/logout",token=token,method="POST")
            except Exception:pass

if __name__=="__main__":
    p=port()
    env=dict(os.environ)
    env["B2B_REAL_WP_ROOT"]=str(ROOT)
    process=subprocess.Popen(["php","-S",f"127.0.0.1:{p}",
        "-t",str(ROOT),str(ROUTER)],cwd=str(ROOT),env=env,
        stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
    try:
        url=f"http://127.0.0.1:{p}/wp-json/excel-herbal-erp/v7"
        for _ in range(120):
            if process.poll() is not None:
                raise RuntimeError("WordPress local PHP HTTP server exited")
            try:
                status,_,_=req(url,"/health")
                if status in (200,401,500):break
            except (OSError,TimeoutError):time.sleep(0.1)
        else:raise RuntimeError("WordPress HTTP endpoint never became ready")
        run(url)
        print(f"REAL WORDPRESS + V7 LOGIN + B2B REST: {CHECKS}/{CHECKS} PASS",flush=True)
    finally:
        process.terminate()
        try:
            _,error=process.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill();_,error=process.communicate(timeout=5)
        if process.returncode not in (0,-15,-9,143):
            print("PHP local server returncode:",process.returncode,file=sys.stderr)
        # Render limited diagnostics without request headers/passwords/tokens.
        if process.returncode not in (0,-15,-9,143):
            print(error.decode("utf-8","replace")[-1200:],file=sys.stderr)
