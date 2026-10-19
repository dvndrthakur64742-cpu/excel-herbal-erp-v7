# V8 v0.19 — Canonical sale and V8 evidence states, one transaction (UAT only)

## Fixed reconciliation defect

The previous V7 canonical B2B writer consumed `eh7_b2b_verified_tenders` but left the original `v8_b2b_verified_tenders`, `v8_b2b_sale_tender_reservations_uat`, `v8_b2b_payment_intents_uat` and `v8_b2b_sale_intents_uat` indicating open/pending states. It could therefore show a posted journal with ostensibly reusable payment evidence.

Now, with the original records **row-locked by `V7UatLockedCheckoutReader` inside the same V7 `Transaction::run`**, the writer uses four scoped, compare-and-swap updates. All must affect exactly one row before sale and idempotency finalization:

1. V7 canonical `eh7_b2b_verified_tenders.consumed_sale_id = sale_id` (existing gate).
2. V8 original verified tender: `consumed_sale_id = sale_id` from NULL and confirmed.
3. V8 reservation: `status = consumed` from reserved; exact company, branch, sale, payment-intent, tender, and quote digest.
4. V8 payment intent: `status = consumed` from awaiting_payment; exact company, branch, ID, INR amount.
5. V8 sale intent: `status = posted` from awaiting_payment; exact company, branch, ID, digest.
6. Canonical sale and idempotency key: final state posted and stable receipt, as before.

`V7UatLockedCheckoutReader` now requires the original payment intent status `awaiting_payment` and returns **trusted, locked** `payment_intent_id` and `uat_tender_id`. The writer refuses missing IDs rather than using browser-provided values. Exact idempotent retry returns the original canonical receipt without consuming or moving stock again.

## Test evidence

- 43/43 same-connection canonical-writer fake DB tests (previous 34). Added missing IDs, fail each original V8 compare-and-swap stage, rollback assertions and repeat-safety checks.
- 47/47 locked-reader tests (previous 46), including consumed payment intent rejection.
- All earlier isolated B2B PHP test suites also PASS locally. PHP CLI available locally, but **no PDO MySQL/MariaDB engine** and no real same-DB transaction concurrency test executed here.

## Release gate — CLOSED

**Never apply this as a production migration.** Development-only `v8_test` database, no WordPress HTTP route or action to invoke posting, four explicit UAT feature flags, no live DB changes, no production deploy or PR merge. The external independently authenticated Cash/PSP bridge remains missing. Owner-approved GST/HSN, tax/discount and reversal rules; real MariaDB concurrency/rollback; validated field remittance and Flutter/device UAT remain required.
