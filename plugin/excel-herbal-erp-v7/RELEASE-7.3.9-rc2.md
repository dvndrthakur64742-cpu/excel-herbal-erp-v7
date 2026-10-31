# Excel Herbal ERP V7 — 7.3.9-rc2 (Distributor Volume Pricing Engine)

Adds a pure, deterministic and auditable `DistributorVolumePricing::quote()` calculation using approved **per-order, per-product quantity slabs**.

- Validates whole-PCS quantity and non-overlapping min/max ranges.
- Supports an open-ended final slab and rejects quantity gaps.
- Uses integer paise accounting, returns decimal strings with exactly two fraction digits and selected price-slab ID.
- Does not blindly apply the new volume price to an existing B2C/field sale; historical invoices and stock cost snapshots are unaffected.
- Includes PHP regression cases for first/middle/top slab, 60-piece example, rounding, invalid prices, overlapping slabs and absent slabs.

**Not finished:** This is the pricing **calculation engine only**. Effective-dated price-list persistence, distributor customer eligibility, discount approval routing, verified 100% cash/UPI collection and atomic order/invoice posting are separate release blockers. A quote cannot issue an invoice.

The new engine is safe to include in the codebase but must not be presented as complete Distributor Sales.
