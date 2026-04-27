# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-04-26

Initial release.

### Added

- Object-oriented `PureGreeks::Option` API for vanilla American and European options.
- Three engines selected automatically by `PureGreeks::Engines::FallbackChain`:
  - **CRR Binomial American** (200 steps) — for American exercise.
  - **Black-Scholes European** (closed form) — for European or as fallback.
  - **Intrinsic** — for `implied_volatility <= 0`.
- All five Greeks per option: delta, gamma, theta (per calendar day), vega (per 1% vol move), rho (per 1% rate move).
- Implied volatility solver via Brent's method (`PureGreeks::ImpliedVolatility::BrentSolver`), invoked by passing `market_price:` instead of `implied_volatility:`.
- `Option#calculation_model` accessor exposes which engine produced the result.
- Custom error hierarchy (`PureGreeks::Error`, `InvalidInputError`, `ExpiredContractError`, `CalculationError`, `IVConvergenceError`).
- Regression suite against ~500 historical option snapshots from production data; methodology and observed drift documented in `REGRESSION_REPORT.md`.
- Performance baselines documented in `BENCHMARKS.md`: ~83 ops/s for American (CRR 200 steps), ~150k ops/s for European (closed form).
