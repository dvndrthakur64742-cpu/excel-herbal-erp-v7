# Employee 360 — canonical Stock Request History (development branch only)

The existing V7 Daily Order already implements request, manager approval/rejection,
and employee stock custody issuance via V7 StockService. This addition does **not**
create a new stock workflow, shadow inventory, or a financial posting.

Employee 360 now has a "Stock Requests" read-only paginated tab calling the
existing /organization/employees/{id}/360/register?type=requests endpoint.

V7 sources:
- daily_cycles: company/employee/branch/business-date scope
- daily_requests: original initial/additional request status and approval/issue actors
- daily_request_lines: requested quantities, pre-aggregated by request
- daily_issue_lines: actually issued quantities, independently pre-aggregated

Approval is NOT proof of issue. Multi-batch issue rows do not multiply requested
quantities. No sale prices, purchase costs, earnings, or GL data returned. The
existing Employee360Service authorization is reused (self/history or manager
hierarchy and branch scope). Pagination retains 1–500, 1–100 row limits and
366-day date limits.

CI must execute canonical V7 PHP register regressions on PHP 8.3, 8.4 and
GitHub-hosted Windows. Flutter source-contract test added; Flutter build/runtime
and real WordPress-device testing are still independent release gates. No
production deployment, PR merge, live DB migration, or provider activation.
