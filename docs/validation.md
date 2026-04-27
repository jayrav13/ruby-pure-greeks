---
title: Validation
---

# Validation

Two layers:

## Hull reference (unit tests)

Every engine is unit-tested against textbook reference values from Hull, *Options, Futures, and Other Derivatives* (11e). For an at-the-money call with `S = K = 100`, `T = 1y`, `r = 5%`, `σ = 20%`, `q = 0`:

| quantity | Hull | tolerance |
|---|---|---|
| Black-Scholes European call | 10.4506 | 1e-3 |
| Black-Scholes European put | 5.5735 | 1e-3 |
| Δ (call) | 0.6368 | 1e-4 |
| Γ | 0.01876 | 1e-5 |
| Θ (per day) | −0.01757 | 1e-4 |
| ν (per 1%) | 0.37524 | 1e-4 |
| ρ (per 1%) | 0.53232 | 1e-3 |

Plus put-call parity: `C − P − (S·e^(−q·T) − K·e^(−r·T)) = 0` to 1e-10.

CRR American is tested against the same Hull inputs (degenerate to European when there's no early-exercise premium) plus the known Hull American put benchmark of 6.0395 vs European 5.5735 to verify early-exercise pickup.

## Regression against Tenor's QuantLib output

Beyond Hull, the gem is regression-tested against ~500 historical option snapshots from Tenor's production database, where Greeks were computed by QuantLib (CRR Binomial American 200-step / BlackCalculator European). Methodology, observed drift, and known limitations are documented in [`REGRESSION_REPORT.md`](https://github.com/jayrav13/ruby-pure-greeks/blob/main/REGRESSION_REPORT.md).

The regression suite is opt-in (`bundle exec rake regression`) — it's slow and has small documented drift in deep-ITM American boundary conditions, so it doesn't gate CI. The Hull unit tests do.

## Fixture provenance

The regression fixture is regenerated manually by the maintainer when the source data changes. The export tool (`tools/golden_dataset_export.rb`) documents the exact SQL query used and the expected JSON shape, so future runs are reproducible.
