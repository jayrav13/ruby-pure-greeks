---
title: How the engines work
---

# How the engines work

`pure_greeks` ships three pricing engines and a deterministic fallback chain that picks one for each call.

## The three engines

1. **Black-Scholes European (closed-form)** — analytic formula for European exercise. Cheap, exact within the model.
2. **CRR Binomial American** — Cox-Ross-Rubinstein binomial tree, 200 steps. Captures early-exercise premium for American options. Greeks are extracted from the tree (delta and gamma from t=0 nodes, theta from t=1 vs t=0, vega and rho via finite difference over re-priced trees).
3. **Intrinsic value** — `max(S - K, 0)` for calls, `max(K - S, 0)` for puts. The terminal fallback when implied volatility is zero or negative.

## Fallback chain

Selection order is fixed and deterministic:

1. If `implied_volatility <= 0`, use **Intrinsic**.
2. Else if `exercise_style == :american`, use **CRR Binomial American**.
3. Else use **Black-Scholes European**.

The engine that produced the result is always exposed on the option:

```ruby
option.calculation_model  # => :crr_binomial_american | :black_scholes_european | :intrinsic
```

If an engine raises, the chain falls through to the next one (American → European → Intrinsic).

## CRR Greeks extraction

The standard "free Greeks" technique used by QuantLib's `BinomialVanillaEngine`:

- **Delta** ≈ `(V[0]_step1 − V[1]_step1) / (S·u − S·d)` — finite difference one step from expiry.
- **Gamma** ≈ `(Δ_upper − Δ_lower) / (½(S·u² − S·d²))` where `Δ_upper` and `Δ_lower` come from step 2.
- **Theta** ≈ `(V[1]_step2 − price) / (2·Δt)` then divided by 365 for per-day units.
- **Vega** and **rho** are computed by re-pricing two more trees with σ + 0.01 and r + 0.01 respectively, then taking the forward difference.

This costs three full tree solves per option; queued for v0.2 optimization (see `BENCHMARKS.md`).

## Why this exists

QuantLib is the industry-standard option pricer, but its Ruby binding is a binary dep that's painful in production: you need a system install, version pinning is fragile, and it's hard to deploy on serverless platforms. `pure_greeks` is a deliberately scoped subset — the vanilla American/European Greeks that most equity-option workloads actually need — implemented in pure Ruby so it installs anywhere `gem install` works.
