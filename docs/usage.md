---
title: Usage
---

# Usage

## Pricing and Greeks (American)

```ruby
require "pure_greeks"

option = PureGreeks::Option.new(
  exercise_style: :american,
  type: :call,
  strike: 150.0,
  expiration: Date.new(2026, 6, 19),
  underlying_price: 148.5,
  implied_volatility: 0.35,
  risk_free_rate: 0.05,
  dividend_yield: 0.0,
  valuation_date: Date.today
)

option.price                # => 4.27
option.delta                # => 0.42
option.gamma                # => 0.018
option.theta                # => -0.012  (per calendar day)
option.vega                 # => 0.31    (per 1% vol move)
option.rho                  # => 0.08    (per 1% rate move)
option.calculation_model    # => :crr_binomial_american
```

## Solving for implied volatility

Pass `market_price:` instead of `implied_volatility:`. The solver uses Brent's method on the Black-Scholes European pricer; for American options with significant early-exercise premium the result is a close approximation, not exact.

```ruby
option = PureGreeks::Option.new(
  exercise_style: :european,
  type: :call,
  strike: 150.0,
  expiration: Date.new(2026, 6, 19),
  underlying_price: 148.5,
  market_price: 5.20,
  risk_free_rate: 0.05,
  dividend_yield: 0.0,
  valuation_date: Date.today
)

option.implied_volatility   # => 0.342
```

## Constructor arguments

| Argument | Type | Notes |
|---|---|---|
| `exercise_style` | `:american` or `:european` | Routes to CRR or Black-Scholes. |
| `type` | `:call` or `:put` | |
| `strike` | Numeric | Must be positive. |
| `expiration` | `Date` | Must be strictly after `valuation_date`. |
| `underlying_price` | Numeric | Must be positive. |
| `implied_volatility` | Numeric | Annualized, decimal (0.35 == 35%). Either this or `market_price`, not both. |
| `market_price` | Numeric | Triggers the IV solver. Either this or `implied_volatility`, not both. |
| `risk_free_rate` | Numeric | Annualized, decimal. |
| `dividend_yield` | Numeric | Annualized, decimal. |
| `valuation_date` | `Date` | The "today" against which `expiration` is measured. |

## Errors

| Error | When |
|---|---|
| `PureGreeks::InvalidInputError` | bad input at construction time (wrong `exercise_style`, wrong `type`, non-positive `strike` or `underlying_price`) |
| `PureGreeks::ExpiredContractError` | subclass of `InvalidInputError`; raised when `expiration <= valuation_date` |
| `PureGreeks::IVConvergenceError` | subclass of `CalculationError`; Brent's method failed to bracket or converge |

All inherit from `PureGreeks::Error`, so `rescue PureGreeks::Error` catches everything.
