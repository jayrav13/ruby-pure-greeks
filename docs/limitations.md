---
title: Limitations
---

# Limitations

`pure_greeks` v0.1 is intentionally scoped. Things it does **not** do:

- **Throughput.** Pure Ruby is roughly 3× slower than QuantLib's C++ for American options. Fine for interactive use and most batch jobs; see [`BENCHMARKS.md`](https://github.com/jayrav13/ruby-pure-greeks/blob/main/BENCHMARKS.md) for measured numbers (~83 ops/s American, ~150k ops/s European on Apple Silicon Ruby 3.2). A native extension is on the v0.2 backlog if real workloads need it.
- **American implied volatility.** The IV solver inverts the Black-Scholes European pricer even for American options. For American options with significant early-exercise premium, the solved IV will be slightly off. v0.2 may add a CRR-based IV solver (slower but exact).
- **Non-vanilla exercise.** No Bermudan, Asian, barrier, or any other exotic exercise style.
- **Discrete dividends.** Dividend yield is treated as a continuous constant. Discrete dividends require a different tree and are out of scope for v0.1.
- **Day-count conventions.** Time-to-expiry uses Actual/365 Fixed. If your reference data uses Actual/360 or 30/360, expect small drifts.
- **Deep-boundary American Greeks.** The 200-step CRR tree pins delta to ±1 and gamma to 0 in regions where smoother engines (e.g. QuantLib with Crank-Nicolson) interpolate. See `REGRESSION_REPORT.md` for the empirical extent.

If any of these blocks your use case, please open an issue describing the workload — that drives v0.2 prioritization.
