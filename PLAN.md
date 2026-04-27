# pure_greeks v0.1.0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a pure-Ruby gem (`pure_greeks`) that computes options Greeks (delta, gamma, theta, vega, rho), prices, and implied volatility for vanilla European and American options — with no Python or QuantLib dependency. Validate against a golden dataset of historical QuantLib outputs from the Tenor codebase.

**Architecture:** Object-oriented public API (`PureGreeks::Option`) backed by a pluggable engine architecture with a three-tier fallback chain (CRR Binomial American → Black-Scholes European → Intrinsic). Engines are stateless calculators; the `Option` class orchestrates engine selection and exposes lazy, cached Greek/price accessors. An IV solver inverts the pricing function via Brent's method.

**Tech Stack:** Ruby 3.2+, RSpec, `distribution` gem (normal CDF/PDF), `bigdecimal` (stdlib, for IV solver bounds), GitHub Actions for CI. No native extensions in v0.1.0 — performance pass at the end determines whether v0.2 needs them.

---

## Origin & Background

This gem extracts and re-implements the Greeks calculation pipeline from the Tenor application (`bin/calculate_greeks.py`), which currently uses QuantLib via a Python subprocess. Rewriting in pure Ruby eliminates the cross-language boundary, makes the math portable for other Ruby projects, and removes the system-level QuantLib dependency.

The reference implementation in Tenor uses three QuantLib engines in fallback order:

1. **CRR Binomial American (200-step)** — handles ~83% of options
2. **Black-Scholes European (analytic)** — fallback for extreme IV that breaks the binomial tree
3. **Intrinsic value** — last resort for zero/negative IV

This plan reproduces that pipeline using stdlib + `distribution` gem, validates numerical agreement against the Tenor production database, and ships a clean OO API.

---

## Public API Design (target shape)

The gem must expose this API. All later tasks must conform.

```ruby
require "pure_greeks"

# Compute Greeks given IV
option = PureGreeks::Option.new(
  exercise_style: :american,        # or :european
  type: :call,                       # or :put
  strike: 150.0,
  expiration: Date.new(2026, 6, 19),
  underlying_price: 148.5,
  implied_volatility: 0.35,
  risk_free_rate: 0.05,
  dividend_yield: 0.0,
  valuation_date: Date.new(2026, 4, 26)
)

option.price                # => Float
option.delta                # => Float
option.gamma                # => Float
option.theta                # => Float (per calendar day)
option.vega                 # => Float (per 1% vol move)
option.rho                  # => Float (per 1% rate move)
option.greeks               # => PureGreeks::Greeks struct (all five + price + model)
option.calculation_model    # => :crr_binomial_american | :black_scholes_european | :intrinsic

# Solve for implied volatility given a market price
option = PureGreeks::Option.new(
  exercise_style: :european,
  type: :call,
  strike: 150.0,
  expiration: Date.new(2026, 6, 19),
  underlying_price: 148.5,
  market_price: 5.20,
  risk_free_rate: 0.05,
  dividend_yield: 0.0,
  valuation_date: Date.new(2026, 4, 26)
)
option.implied_volatility   # => Float (solved via Brent's method)
```

---

## File Structure

```
pure_greeks/
├── pure_greeks.gemspec
├── Gemfile
├── Rakefile
├── README.md
├── CHANGELOG.md
├── LICENSE.txt
├── .rspec
├── .rubocop.yml
├── .github/workflows/ci.yml
├── lib/
│   ├── pure_greeks.rb                                 # Top-level require + version
│   ├── pure_greeks/
│   │   ├── version.rb                                 # VERSION constant
│   │   ├── option.rb                                  # Public OO entry point
│   │   ├── greeks.rb                                  # Greeks value object (Data)
│   │   ├── errors.rb                                  # Custom error classes
│   │   ├── math/
│   │   │   └── normal.rb                              # Normal CDF/PDF (wraps `distribution`)
│   │   ├── engines/
│   │   │   ├── base.rb                                # Abstract engine interface
│   │   │   ├── black_scholes_european.rb              # Closed-form analytic engine
│   │   │   ├── crr_binomial_american.rb               # 200-step binomial tree engine
│   │   │   ├── intrinsic.rb                           # Zero-IV fallback engine
│   │   │   └── fallback_chain.rb                      # Tier orchestrator
│   │   └── implied_volatility/
│   │       └── brent_solver.rb                        # Brent's method root finder
├── spec/
│   ├── spec_helper.rb
│   ├── pure_greeks_spec.rb
│   ├── option_spec.rb
│   ├── greeks_spec.rb
│   ├── math/
│   │   └── normal_spec.rb
│   ├── engines/
│   │   ├── black_scholes_european_spec.rb
│   │   ├── crr_binomial_american_spec.rb
│   │   ├── intrinsic_spec.rb
│   │   └── fallback_chain_spec.rb
│   ├── implied_volatility/
│   │   └── brent_solver_spec.rb
│   └── regression/
│       ├── golden_dataset_spec.rb                     # Compares to Tenor QuantLib outputs
│       └── fixtures/
│           └── tenor_golden.json                      # Exported via tools/golden_dataset_export.rb
├── bench/
│   ├── single_option.rb
│   └── batch.rb
└── tools/
    └── golden_dataset_export.rb                       # Pulls from Tenor prod DB via MCP
```

**Responsibility map:**

| File | Responsibility |
|------|----------------|
| `option.rb` | Public OO API. Validates inputs, picks engine, exposes lazy Greek/price accessors, runs IV solver when `market_price` given. |
| `greeks.rb` | Immutable value object holding `delta`, `gamma`, `theta`, `vega`, `rho`, `price`, `model`. |
| `math/normal.rb` | Wraps `Distribution::Normal.cdf` / `.pdf` behind a stable internal namespace. Single point of change if the dependency is swapped. |
| `engines/base.rb` | Defines the engine interface: `#calculate(option_data) → Greeks`. |
| `engines/black_scholes_european.rb` | Closed-form formulas for European option price + Greeks. |
| `engines/crr_binomial_american.rb` | 200-step Cox-Ross-Rubinstein tree. Backward induction with early-exercise check. Finite-difference vega/rho. |
| `engines/intrinsic.rb` | Returns intrinsic value + binary delta. Used for zero/negative IV. |
| `engines/fallback_chain.rb` | Tries engines in order (American → European → Intrinsic), catching numerical failures. |
| `implied_volatility/brent_solver.rb` | Brent's method root finder. Brackets IV between `[1e-6, 5.0]` and inverts the price function. |
| `tools/golden_dataset_export.rb` | One-off script that pulls (snapshot inputs, computed Greeks) from Tenor's `options.greeks` table via the MCP `mcp__postgres-prod__query` tool, writes JSON fixture. |

---

## Prerequisites for the Implementing Session

The session executing this plan must have:

1. **Ruby 3.2+** installed (`ruby -v`)
2. **Bundler** (`gem install bundler`)
3. **Tenor MCP access** — specifically, `mcp__postgres-prod__query` must be available to pull the golden dataset in Phase 7. Confirm with `mcp` tool list before starting Phase 7. If unavailable, skip Phase 7 and flag for follow-up.

Per Tenor `CLAUDE.md` memory: writes against the production DB require explicit user permission. Phase 7 is **read-only** (`SELECT` only) — the export tool must enforce that.

---

## Phase 0: Project Skeleton

### Task 1: Initialize gem skeleton with bundler

**Files:**
- Scaffold via `bundle gem` in a temp dir, then copy results into `~/Code/pure_greeks/` to preserve the existing `.git` and `PLAN.md`.

The repo already exists at `~/Code/pure_greeks/` with an initial commit on `main` containing `PLAN.md`. `bundle gem` requires a non-existent target directory, so we scaffold to a temp location and copy files in.

- [ ] **Step 1: Scaffold to temp location**

```bash
cd /tmp
rm -rf /tmp/pure_greeks_scaffold
bundle gem pure_greeks_scaffold --test=rspec --linter=rubocop --ci=github --no-mit --no-coc --no-changelog
```

Expected: `/tmp/pure_greeks_scaffold/` exists with full gem layout (lib/, spec/, gemspec, Rakefile, .git, etc.).

- [ ] **Step 2: Drop the scaffold's git so we don't overwrite ours**

```bash
rm -rf /tmp/pure_greeks_scaffold/.git
```

- [ ] **Step 3: Rename gem internals from `pure_greeks_scaffold` → `pure_greeks`**

The scaffold uses the dir name throughout. Rename:

```bash
cd /tmp/pure_greeks_scaffold
mv pure_greeks_scaffold.gemspec pure_greeks.gemspec
mv lib/pure_greeks_scaffold lib/pure_greeks
mv lib/pure_greeks_scaffold.rb lib/pure_greeks.rb
mv spec/pure_greeks_scaffold_spec.rb spec/pure_greeks_spec.rb
# Replace identifiers inside files (sed -i '' is BSD/macOS syntax)
grep -rl 'pure_greeks_scaffold\|PureGreeksScaffold' . | xargs sed -i '' 's/PureGreeksScaffold/PureGreeks/g; s/pure_greeks_scaffold/pure_greeks/g'
```

- [ ] **Step 4: Copy scaffold into our repo**

```bash
cd /tmp/pure_greeks_scaffold
# Use cp -r with /. to copy hidden dotfiles (.rspec, .rubocop.yml, .github/) too
cp -r ./. ~/Code/pure_greeks/
rm -rf /tmp/pure_greeks_scaffold
```

- [ ] **Step 5: Set Ruby version floor**

Edit `~/Code/pure_greeks/pure_greeks.gemspec`:

```ruby
spec.required_ruby_version = ">= 3.2.0"
```

- [ ] **Step 6: Verify skeleton**

```bash
cd ~/Code/pure_greeks
bundle install
bundle exec rspec
```

Expected: bundler installs deps; `rspec` reports `0 examples, 0 failures` (or whatever scaffold-default specs ran — clean either way).

- [ ] **Step 7: Commit**

```bash
git add .
git commit -m "chore: initialize gem skeleton with bundler"
```

### Task 2: Add runtime + dev dependencies

**Files:**
- Modify: `pure_greeks.gemspec`
- Modify: `Gemfile`

- [ ] **Step 1: Add `distribution` runtime dependency**

Edit `pure_greeks.gemspec`, inside the `Gem::Specification.new` block:

```ruby
spec.add_dependency "distribution", "~> 0.8"
```

- [ ] **Step 2: Install**

Run: `bundle install`
Expected: `distribution` installed.

- [ ] **Step 3: Verify the require path works**

Run: `bundle exec ruby -e "require 'distribution'; puts Distribution::Normal.cdf(0.0)"`
Expected: `0.5`

- [ ] **Step 4: Commit**

```bash
git add pure_greeks.gemspec Gemfile.lock
git commit -m "feat: add distribution gem for normal CDF/PDF"
```

### Task 3: Configure RSpec

**Files:**
- Modify: `.rspec`
- Modify: `spec/spec_helper.rb`

- [ ] **Step 1: Update `.rspec`**

Replace contents of `.rspec`:

```
--require spec_helper
--format documentation
--color
```

- [ ] **Step 2: Verify spec_helper is sane**

Read `spec/spec_helper.rb`. Ensure it requires `pure_greeks`:

```ruby
require "pure_greeks"

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
```

- [ ] **Step 3: Run rspec to confirm**

Run: `bundle exec rspec`
Expected: 0 examples, 0 failures.

- [ ] **Step 4: Commit**

```bash
git add .rspec spec/spec_helper.rb
git commit -m "chore: configure RSpec output and require"
```

---

## Phase 1: Math Foundations

### Task 4: Normal distribution wrapper

**Files:**
- Create: `lib/pure_greeks/math/normal.rb`
- Test: `spec/math/normal_spec.rb`

Wraps the `distribution` gem behind an internal namespace. This is the only place the gem touches `Distribution::Normal` directly — if the dep is swapped, only this file changes.

- [ ] **Step 1: Write the failing tests**

Create `spec/math/normal_spec.rb`:

```ruby
require "pure_greeks/math/normal"

RSpec.describe PureGreeks::Math::Normal do
  describe ".cdf" do
    it "returns 0.5 at zero" do
      expect(described_class.cdf(0.0)).to be_within(1e-10).of(0.5)
    end

    it "returns ~0.8413 at one std dev" do
      expect(described_class.cdf(1.0)).to be_within(1e-4).of(0.8413)
    end

    it "returns ~0.9772 at two std devs" do
      expect(described_class.cdf(2.0)).to be_within(1e-4).of(0.9772)
    end

    it "returns symmetric values around zero" do
      expect(described_class.cdf(-1.5) + described_class.cdf(1.5)).to be_within(1e-10).of(1.0)
    end
  end

  describe ".pdf" do
    it "returns 1/sqrt(2*pi) at zero" do
      expect(described_class.pdf(0.0)).to be_within(1e-10).of(1.0 / ::Math.sqrt(2 * ::Math::PI))
    end

    it "is symmetric" do
      expect(described_class.pdf(-1.7)).to be_within(1e-10).of(described_class.pdf(1.7))
    end
  end
end
```

- [ ] **Step 2: Run, expect failure**

Run: `bundle exec rspec spec/math/normal_spec.rb`
Expected: `LoadError` — `pure_greeks/math/normal` does not exist.

- [ ] **Step 3: Implement**

Create `lib/pure_greeks/math/normal.rb`:

```ruby
require "distribution"

module PureGreeks
  module Math
    module Normal
      def self.cdf(x)
        Distribution::Normal.cdf(x)
      end

      def self.pdf(x)
        Distribution::Normal.pdf(x)
      end
    end
  end
end
```

- [ ] **Step 4: Run, expect pass**

Run: `bundle exec rspec spec/math/normal_spec.rb`
Expected: 6 examples, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/pure_greeks/math/normal.rb spec/math/normal_spec.rb
git commit -m "feat: add Normal distribution wrapper"
```

### Task 5: Greeks value object

**Files:**
- Create: `lib/pure_greeks/greeks.rb`
- Test: `spec/greeks_spec.rb`

Immutable `Data` class. Holds the five Greeks plus price plus the engine that produced them.

- [ ] **Step 1: Write the failing tests**

Create `spec/greeks_spec.rb`:

```ruby
require "pure_greeks/greeks"

RSpec.describe PureGreeks::Greeks do
  let(:greeks) do
    described_class.new(
      delta: 0.5,
      gamma: 0.02,
      theta: -0.01,
      vega: 0.15,
      rho: 0.08,
      price: 4.25,
      model: :black_scholes_european
    )
  end

  it "exposes all six numeric fields" do
    expect(greeks.delta).to eq(0.5)
    expect(greeks.gamma).to eq(0.02)
    expect(greeks.theta).to eq(-0.01)
    expect(greeks.vega).to eq(0.15)
    expect(greeks.rho).to eq(0.08)
    expect(greeks.price).to eq(4.25)
  end

  it "exposes the model symbol" do
    expect(greeks.model).to eq(:black_scholes_european)
  end

  it "is immutable" do
    expect { greeks.delta = 0.7 }.to raise_error(NoMethodError)
  end
end
```

- [ ] **Step 2: Run, expect failure**

Run: `bundle exec rspec spec/greeks_spec.rb`
Expected: LoadError.

- [ ] **Step 3: Implement**

Create `lib/pure_greeks/greeks.rb`:

```ruby
module PureGreeks
  Greeks = Data.define(:delta, :gamma, :theta, :vega, :rho, :price, :model)
end
```

- [ ] **Step 4: Run, expect pass**

Run: `bundle exec rspec spec/greeks_spec.rb`
Expected: 3 examples, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/pure_greeks/greeks.rb spec/greeks_spec.rb
git commit -m "feat: add Greeks value object"
```

### Task 6: Custom error classes

**Files:**
- Create: `lib/pure_greeks/errors.rb`

- [ ] **Step 1: Implement**

Create `lib/pure_greeks/errors.rb`:

```ruby
module PureGreeks
  class Error < StandardError; end
  class InvalidInputError < Error; end
  class ExpiredContractError < InvalidInputError; end
  class CalculationError < Error; end
  class IVConvergenceError < CalculationError; end
end
```

- [ ] **Step 2: Commit**

```bash
git add lib/pure_greeks/errors.rb
git commit -m "feat: add error class hierarchy"
```

---

## Phase 2: Black-Scholes European Engine

### Task 7: Black-Scholes pricing — call

**Files:**
- Create: `lib/pure_greeks/engines/black_scholes_european.rb` (incremental — pricing first)
- Test: `spec/engines/black_scholes_european_spec.rb`

**Reference values** (Hull, 11e — Spot=100, Strike=100, T=1.0 yr, r=5%, σ=20%, q=0):
- Call price = 10.4506
- Put price = 5.5735

**Black-Scholes formulas:**

```
d1 = (ln(S/K) + (r - q + σ²/2)·T) / (σ·√T)
d2 = d1 − σ·√T
Call = S·e^(−q·T)·N(d1) − K·e^(−r·T)·N(d2)
Put  = K·e^(−r·T)·N(−d2) − S·e^(−q·T)·N(−d1)
```

- [ ] **Step 1: Write failing test for call price**

Create `spec/engines/black_scholes_european_spec.rb`:

```ruby
require "pure_greeks/engines/black_scholes_european"

RSpec.describe PureGreeks::Engines::BlackScholesEuropean do
  let(:hull_inputs) do
    {
      type: :call,
      strike: 100.0,
      underlying_price: 100.0,
      time_to_expiry: 1.0,
      implied_volatility: 0.20,
      risk_free_rate: 0.05,
      dividend_yield: 0.0
    }
  end

  describe ".price" do
    it "matches Hull reference for at-the-money call" do
      expect(described_class.price(**hull_inputs)).to be_within(1e-3).of(10.4506)
    end
  end
end
```

- [ ] **Step 2: Run, expect failure**

Run: `bundle exec rspec spec/engines/black_scholes_european_spec.rb`
Expected: LoadError.

- [ ] **Step 3: Implement**

Create `lib/pure_greeks/engines/black_scholes_european.rb`:

```ruby
require "pure_greeks/math/normal"

module PureGreeks
  module Engines
    module BlackScholesEuropean
      module_function

      def price(type:, strike:, underlying_price:, time_to_expiry:, implied_volatility:, risk_free_rate:, dividend_yield:)
        d1, d2 = d1_d2(strike, underlying_price, time_to_expiry, implied_volatility, risk_free_rate, dividend_yield)
        s_disc = underlying_price * ::Math.exp(-dividend_yield * time_to_expiry)
        k_disc = strike * ::Math.exp(-risk_free_rate * time_to_expiry)

        if type == :call
          s_disc * Math::Normal.cdf(d1) - k_disc * Math::Normal.cdf(d2)
        else
          k_disc * Math::Normal.cdf(-d2) - s_disc * Math::Normal.cdf(-d1)
        end
      end

      def d1_d2(strike, spot, t, sigma, r, q)
        sqrt_t = ::Math.sqrt(t)
        d1 = (::Math.log(spot / strike) + (r - q + 0.5 * sigma**2) * t) / (sigma * sqrt_t)
        d2 = d1 - sigma * sqrt_t
        [d1, d2]
      end
    end
  end
end
```

- [ ] **Step 4: Run, expect pass**

Run: `bundle exec rspec spec/engines/black_scholes_european_spec.rb`
Expected: 1 example, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/pure_greeks/engines/black_scholes_european.rb spec/engines/black_scholes_european_spec.rb
git commit -m "feat: add Black-Scholes European call pricing"
```

### Task 8: Black-Scholes pricing — put + put-call parity

**Files:**
- Modify: `spec/engines/black_scholes_european_spec.rb`

- [ ] **Step 1: Add put price test**

Append to `spec/engines/black_scholes_european_spec.rb`, inside `describe ".price"`:

```ruby
it "matches Hull reference for at-the-money put" do
  expect(described_class.price(**hull_inputs.merge(type: :put))).to be_within(1e-3).of(5.5735)
end

it "satisfies put-call parity" do
  call = described_class.price(**hull_inputs)
  put = described_class.price(**hull_inputs.merge(type: :put))
  s, k, r, q, t = 100.0, 100.0, 0.05, 0.0, 1.0
  parity = call - put - (s * ::Math.exp(-q * t) - k * ::Math.exp(-r * t))
  expect(parity).to be_within(1e-10).of(0.0)
end
```

- [ ] **Step 2: Run, expect pass (put already implemented in Task 7)**

Run: `bundle exec rspec spec/engines/black_scholes_european_spec.rb`
Expected: 3 examples, 0 failures.

- [ ] **Step 3: Commit**

```bash
git add spec/engines/black_scholes_european_spec.rb
git commit -m "test: verify Black-Scholes put pricing and put-call parity"
```

### Task 9: Black-Scholes Greeks (delta, gamma, theta, vega, rho)

**Files:**
- Modify: `lib/pure_greeks/engines/black_scholes_european.rb`
- Modify: `spec/engines/black_scholes_european_spec.rb`

**Reference Greeks** (Hull params, ATM call):
- Delta = N(d1) = 0.6368
- Gamma = N'(d1)/(S·σ·√T) = 0.01876
- Theta (per year) = −6.4140 → per day = −0.01757
- Vega (per 1.0 vol move) = 37.524 → per 1% = 0.37524
- Rho (per 1.0 rate move) = 53.232 → per 1% = 0.53232

**Greek formulas:**

```
Δ_call = e^(−q·T)·N(d1)
Δ_put  = −e^(−q·T)·N(−d1)
Γ      = e^(−q·T)·φ(d1)/(S·σ·√T)              (same call/put)
Θ_call = −S·φ(d1)·σ·e^(−q·T)/(2·√T) − r·K·e^(−r·T)·N(d2) + q·S·e^(−q·T)·N(d1)
Θ_put  = −S·φ(d1)·σ·e^(−q·T)/(2·√T) + r·K·e^(−r·T)·N(−d2) − q·S·e^(−q·T)·N(−d1)
ν      = S·e^(−q·T)·φ(d1)·√T                  (same call/put; per 1.0 vol)
ρ_call = K·T·e^(−r·T)·N(d2)                    (per 1.0 rate)
ρ_put  = −K·T·e^(−r·T)·N(−d2)                  (per 1.0 rate)
```

The engine returns theta scaled per **calendar day** (theta_per_year / 365), vega per **1% move** (vega / 100), rho per **1% move** (rho / 100) — matching the Tenor reference implementation.

- [ ] **Step 1: Write failing test for full Greeks output**

Append to `spec/engines/black_scholes_european_spec.rb`:

```ruby
describe ".calculate" do
  it "returns Greeks struct matching Hull reference for ATM call" do
    g = described_class.calculate(**hull_inputs)
    expect(g.price).to be_within(1e-3).of(10.4506)
    expect(g.delta).to be_within(1e-4).of(0.6368)
    expect(g.gamma).to be_within(1e-5).of(0.01876)
    expect(g.theta).to be_within(1e-4).of(-0.01757)
    expect(g.vega).to be_within(1e-4).of(0.37524)
    expect(g.rho).to be_within(1e-3).of(0.53232)
    expect(g.model).to eq(:black_scholes_european)
  end

  it "returns negative delta for put" do
    g = described_class.calculate(**hull_inputs.merge(type: :put))
    expect(g.delta).to be_within(1e-4).of(-0.3632)
  end
end
```

- [ ] **Step 2: Run, expect failure**

Run: `bundle exec rspec spec/engines/black_scholes_european_spec.rb`
Expected: NoMethodError on `.calculate`.

- [ ] **Step 3: Implement `.calculate`**

Replace `lib/pure_greeks/engines/black_scholes_european.rb` contents:

```ruby
require "pure_greeks/math/normal"
require "pure_greeks/greeks"

module PureGreeks
  module Engines
    module BlackScholesEuropean
      module_function

      def calculate(type:, strike:, underlying_price:, time_to_expiry:, implied_volatility:, risk_free_rate:, dividend_yield:)
        d1, d2 = d1_d2(strike, underlying_price, time_to_expiry, implied_volatility, risk_free_rate, dividend_yield)
        sqrt_t = ::Math.sqrt(time_to_expiry)
        s_disc = underlying_price * ::Math.exp(-dividend_yield * time_to_expiry)
        k_disc = strike * ::Math.exp(-risk_free_rate * time_to_expiry)
        nd1 = Math::Normal.cdf(d1)
        nd2 = Math::Normal.cdf(d2)
        n_neg_d1 = Math::Normal.cdf(-d1)
        n_neg_d2 = Math::Normal.cdf(-d2)
        pdf_d1 = Math::Normal.pdf(d1)

        price = type == :call ? s_disc * nd1 - k_disc * nd2 : k_disc * n_neg_d2 - s_disc * n_neg_d1
        delta = type == :call ? ::Math.exp(-dividend_yield * time_to_expiry) * nd1 : -::Math.exp(-dividend_yield * time_to_expiry) * n_neg_d1
        gamma = ::Math.exp(-dividend_yield * time_to_expiry) * pdf_d1 / (underlying_price * implied_volatility * sqrt_t)

        theta_year =
          if type == :call
            -s_disc * pdf_d1 * implied_volatility / (2 * sqrt_t) -
              risk_free_rate * k_disc * nd2 +
              dividend_yield * s_disc * nd1
          else
            -s_disc * pdf_d1 * implied_volatility / (2 * sqrt_t) +
              risk_free_rate * k_disc * n_neg_d2 -
              dividend_yield * s_disc * n_neg_d1
          end

        vega_unit = s_disc * pdf_d1 * sqrt_t
        rho_unit = type == :call ? k_disc * time_to_expiry * nd2 : -k_disc * time_to_expiry * n_neg_d2

        Greeks.new(
          delta: delta,
          gamma: gamma,
          theta: theta_year / 365.0,
          vega: vega_unit / 100.0,
          rho: rho_unit / 100.0,
          price: price,
          model: :black_scholes_european
        )
      end

      def price(**args)
        calculate(**args).price
      end

      def d1_d2(strike, spot, t, sigma, r, q)
        sqrt_t = ::Math.sqrt(t)
        d1 = (::Math.log(spot / strike) + (r - q + 0.5 * sigma**2) * t) / (sigma * sqrt_t)
        d2 = d1 - sigma * sqrt_t
        [d1, d2]
      end
    end
  end
end
```

- [ ] **Step 4: Run, expect pass**

Run: `bundle exec rspec spec/engines/black_scholes_european_spec.rb`
Expected: 5 examples, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/pure_greeks/engines/black_scholes_european.rb spec/engines/black_scholes_european_spec.rb
git commit -m "feat: add Black-Scholes European Greeks (delta, gamma, theta, vega, rho)"
```

---

## Phase 3: CRR Binomial American Engine

### Task 10: CRR tree builder

**Files:**
- Create: `lib/pure_greeks/engines/crr_binomial_american.rb` (incremental — tree first)
- Test: `spec/engines/crr_binomial_american_spec.rb`

**CRR parameters** (Cox-Ross-Rubinstein):
```
dt = T / N
u = exp(σ·√dt)
d = 1/u
p = (exp((r-q)·dt) - d) / (u - d)        # risk-neutral up-probability
disc = exp(-r·dt)                          # one-step discount
```

The tree has N+1 leaf nodes at time T, with spot at leaf `j` being `S · u^(N-j) · d^j` for `j ∈ [0, N]`.

- [ ] **Step 1: Write failing test for tree parameters**

Create `spec/engines/crr_binomial_american_spec.rb`:

```ruby
require "pure_greeks/engines/crr_binomial_american"

RSpec.describe PureGreeks::Engines::CrrBinomialAmerican do
  describe ".tree_parameters" do
    it "computes u, d, p, disc for given inputs" do
      params = described_class.tree_parameters(
        time_to_expiry: 1.0,
        steps: 200,
        implied_volatility: 0.20,
        risk_free_rate: 0.05,
        dividend_yield: 0.0
      )
      dt = 1.0 / 200.0
      expect(params[:dt]).to be_within(1e-12).of(dt)
      expect(params[:u]).to be_within(1e-10).of(::Math.exp(0.20 * ::Math.sqrt(dt)))
      expect(params[:d]).to be_within(1e-10).of(1.0 / params[:u])
      expect(params[:p]).to be > 0.0
      expect(params[:p]).to be < 1.0
      expect(params[:disc]).to be_within(1e-10).of(::Math.exp(-0.05 * dt))
    end
  end
end
```

- [ ] **Step 2: Run, expect failure**

Run: `bundle exec rspec spec/engines/crr_binomial_american_spec.rb`
Expected: LoadError.

- [ ] **Step 3: Implement**

Create `lib/pure_greeks/engines/crr_binomial_american.rb`:

```ruby
module PureGreeks
  module Engines
    module CrrBinomialAmerican
      DEFAULT_STEPS = 200

      module_function

      def tree_parameters(time_to_expiry:, steps:, implied_volatility:, risk_free_rate:, dividend_yield:)
        dt = time_to_expiry / steps.to_f
        u = ::Math.exp(implied_volatility * ::Math.sqrt(dt))
        d = 1.0 / u
        p = (::Math.exp((risk_free_rate - dividend_yield) * dt) - d) / (u - d)
        disc = ::Math.exp(-risk_free_rate * dt)
        { dt: dt, u: u, d: d, p: p, disc: disc }
      end
    end
  end
end
```

- [ ] **Step 4: Run, expect pass**

Run: `bundle exec rspec spec/engines/crr_binomial_american_spec.rb`
Expected: 1 example, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/pure_greeks/engines/crr_binomial_american.rb spec/engines/crr_binomial_american_spec.rb
git commit -m "feat: add CRR tree parameter computation"
```

### Task 11: CRR backward induction — pricing only

**Files:**
- Modify: `lib/pure_greeks/engines/crr_binomial_american.rb`
- Modify: `spec/engines/crr_binomial_american_spec.rb`

**Algorithm:**
1. Build leaf payoff vector: for each leaf `j ∈ [0, N]`, `payoff[j] = max(0, ε·(S·u^(N-j)·d^j − K))` where `ε = +1` for call, `-1` for put.
2. Iterate backward: at step `i = N-1, …, 0`, for each node `j ∈ [0, i]`:
   - `continuation = disc · (p · V[j] + (1-p) · V[j+1])`
   - `spot_at_node = S · u^(i-j) · d^j`
   - `intrinsic = max(0, ε·(spot_at_node − K))`
   - `V[j] = max(continuation, intrinsic)`  ← American early-exercise
3. Return `V[0]`.

**Reference value:** American put with no dividends and no early exercise should equal European put. Use Hull params (S=K=100, σ=20%, r=5%, q=0, T=1):
- European put = 5.5735
- American put = 6.0395 (early exercise has value)
- American call (no div) = European call = 10.4506

- [ ] **Step 1: Write failing test**

Append to `spec/engines/crr_binomial_american_spec.rb`:

```ruby
let(:hull_inputs) do
  {
    type: :call,
    strike: 100.0,
    underlying_price: 100.0,
    time_to_expiry: 1.0,
    implied_volatility: 0.20,
    risk_free_rate: 0.05,
    dividend_yield: 0.0,
    steps: 200
  }
end

describe ".price" do
  it "American call with no dividends matches European call (Hull ATM)" do
    expect(described_class.price(**hull_inputs)).to be_within(0.02).of(10.4506)
  end

  it "American put with dividends > European put (early exercise has value)" do
    am_put = described_class.price(**hull_inputs.merge(type: :put))
    expect(am_put).to be_within(0.05).of(6.0395)
    expect(am_put).to be > 5.5735
  end
end
```

- [ ] **Step 2: Run, expect failure**

Run: `bundle exec rspec spec/engines/crr_binomial_american_spec.rb`
Expected: NoMethodError.

- [ ] **Step 3: Implement backward induction**

Append to `lib/pure_greeks/engines/crr_binomial_american.rb` (inside the module):

```ruby
def price(type:, strike:, underlying_price:, time_to_expiry:, implied_volatility:, risk_free_rate:, dividend_yield:, steps: DEFAULT_STEPS)
  params = tree_parameters(
    time_to_expiry: time_to_expiry,
    steps: steps,
    implied_volatility: implied_volatility,
    risk_free_rate: risk_free_rate,
    dividend_yield: dividend_yield
  )
  backward_induct(type, strike, underlying_price, steps, params)
end

def backward_induct(type, strike, spot, steps, params)
  u = params[:u]
  d = params[:d]
  p = params[:p]
  disc = params[:disc]
  sign = type == :call ? 1.0 : -1.0

  values = Array.new(steps + 1)
  (0..steps).each do |j|
    spot_at_leaf = spot * (u**(steps - j)) * (d**j)
    values[j] = [0.0, sign * (spot_at_leaf - strike)].max
  end

  (steps - 1).downto(0) do |i|
    (0..i).each do |j|
      continuation = disc * (p * values[j] + (1 - p) * values[j + 1])
      spot_at_node = spot * (u**(i - j)) * (d**j)
      intrinsic = [0.0, sign * (spot_at_node - strike)].max
      values[j] = [continuation, intrinsic].max
    end
  end

  values[0]
end
```

- [ ] **Step 4: Run, expect pass**

Run: `bundle exec rspec spec/engines/crr_binomial_american_spec.rb`
Expected: 3 examples, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/pure_greeks/engines/crr_binomial_american.rb spec/engines/crr_binomial_american_spec.rb
git commit -m "feat: add CRR backward induction with early-exercise"
```

### Task 12: CRR delta + gamma extraction from tree

**Files:**
- Modify: `lib/pure_greeks/engines/crr_binomial_american.rb`
- Modify: `spec/engines/crr_binomial_american_spec.rb`

**Approach:** During backward induction, retain the values at step `i = 2` (three nodes). Then:

```
Delta ≈ (V[0]_step1 - V[1]_step1) / (S·u - S·d)
Gamma ≈ (Δ_upper - Δ_lower) / (0.5·(S·u² - S·d²))
        where Δ_upper = (V[0]_step2 - V[1]_step2) / (S·u² - S·u·d)
              Δ_lower = (V[1]_step2 - V[2]_step2) / (S·u·d - S·d²)
```

This is the standard "free" Delta/Gamma extraction technique used by QuantLib's `BinomialVanillaEngine`.

- [ ] **Step 1: Write failing test**

Append to `spec/engines/crr_binomial_american_spec.rb`:

```ruby
describe ".calculate" do
  it "returns Greeks struct for ATM American call (matches BS within tree tolerance)" do
    g = described_class.calculate(**hull_inputs)
    expect(g.price).to be_within(0.02).of(10.4506)
    expect(g.delta).to be_within(0.005).of(0.6368)
    expect(g.gamma).to be_within(0.001).of(0.01876)
    expect(g.model).to eq(:crr_binomial_american)
  end
end
```

- [ ] **Step 2: Run, expect failure**

Run: `bundle exec rspec spec/engines/crr_binomial_american_spec.rb`
Expected: NoMethodError on `.calculate`.

- [ ] **Step 3: Refactor — capture step-1 and step-2 values**

Modify `backward_induct` to optionally return intermediate values, and add a `calculate` method. Replace the `def price` and `def backward_induct` block with:

```ruby
def calculate(type:, strike:, underlying_price:, time_to_expiry:, implied_volatility:, risk_free_rate:, dividend_yield:, steps: DEFAULT_STEPS)
  params = tree_parameters(
    time_to_expiry: time_to_expiry,
    steps: steps,
    implied_volatility: implied_volatility,
    risk_free_rate: risk_free_rate,
    dividend_yield: dividend_yield
  )
  result = backward_induct_with_intermediates(type, strike, underlying_price, steps, params)
  price = result[:price]
  v_step1 = result[:step1]
  v_step2 = result[:step2]
  u = params[:u]
  d = params[:d]

  # Delta from step 1
  delta = (v_step1[0] - v_step1[1]) / (underlying_price * u - underlying_price * d)

  # Gamma from step 2
  s_uu = underlying_price * u * u
  s_ud = underlying_price * u * d
  s_dd = underlying_price * d * d
  delta_upper = (v_step2[0] - v_step2[1]) / (s_uu - s_ud)
  delta_lower = (v_step2[1] - v_step2[2]) / (s_ud - s_dd)
  gamma = (delta_upper - delta_lower) / (0.5 * (s_uu - s_dd))

  # Theta and vega/rho deferred to next tasks
  PureGreeks::Greeks.new(
    delta: delta,
    gamma: gamma,
    theta: 0.0,
    vega: 0.0,
    rho: 0.0,
    price: price,
    model: :crr_binomial_american
  )
end

def price(**args)
  calculate(**args).price
end

def backward_induct_with_intermediates(type, strike, spot, steps, params)
  u = params[:u]
  d = params[:d]
  p = params[:p]
  disc = params[:disc]
  sign = type == :call ? 1.0 : -1.0

  values = Array.new(steps + 1)
  (0..steps).each do |j|
    spot_at_leaf = spot * (u**(steps - j)) * (d**j)
    values[j] = [0.0, sign * (spot_at_leaf - strike)].max
  end

  step2 = nil
  step1 = nil

  (steps - 1).downto(0) do |i|
    (0..i).each do |j|
      continuation = disc * (p * values[j] + (1 - p) * values[j + 1])
      spot_at_node = spot * (u**(i - j)) * (d**j)
      intrinsic = [0.0, sign * (spot_at_node - strike)].max
      values[j] = [continuation, intrinsic].max
    end
    step2 = values[0..2].dup if i == 2
    step1 = values[0..1].dup if i == 1
  end

  { price: values[0], step1: step1, step2: step2 }
end

require "pure_greeks/greeks"
```

Move the `require "pure_greeks/greeks"` to the top of the file (above the module definition).

- [ ] **Step 4: Run, expect pass**

Run: `bundle exec rspec spec/engines/crr_binomial_american_spec.rb`
Expected: 4 examples, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/pure_greeks/engines/crr_binomial_american.rb spec/engines/crr_binomial_american_spec.rb
git commit -m "feat: extract delta and gamma from CRR tree"
```

### Task 13: CRR theta extraction

**Files:**
- Modify: `lib/pure_greeks/engines/crr_binomial_american.rb`
- Modify: `spec/engines/crr_binomial_american_spec.rb`

**Approach:** Theta is approximated by `(V_step2[1] - V_step0) / (2·dt)` then divided by 365 to convert to per-day. The middle-node value at step 2 corresponds to spot ≈ S, two time steps earlier. This is the standard QuantLib `BinomialVanillaEngine` theta technique.

- [ ] **Step 1: Write failing test**

Append to `describe ".calculate"`:

```ruby
it "computes theta close to Black-Scholes equivalent" do
  g = described_class.calculate(**hull_inputs)
  # BS theta for ATM call ≈ -0.01757 per day
  expect(g.theta).to be_within(0.002).of(-0.01757)
end
```

- [ ] **Step 2: Run, expect failure**

Expected: theta is 0.0, test fails.

- [ ] **Step 3: Implement theta**

In `calculate`, replace `theta: 0.0,` with:

```ruby
theta: (v_step2[1] - price) / (2.0 * params[:dt]) / 365.0,
```

- [ ] **Step 4: Run, expect pass**

Run: `bundle exec rspec spec/engines/crr_binomial_american_spec.rb`
Expected: 5 examples, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/pure_greeks/engines/crr_binomial_american.rb spec/engines/crr_binomial_american_spec.rb
git commit -m "feat: extract theta from CRR tree"
```

### Task 14: CRR vega + rho via finite difference

**Files:**
- Modify: `lib/pure_greeks/engines/crr_binomial_american.rb`
- Modify: `spec/engines/crr_binomial_american_spec.rb`

**Approach** (matches Tenor reference):

```
vega = (price(σ + 0.01) - price(σ)) / (0.01 * 100)    # per 1% vol move
rho  = (price(r + 0.01) - price(r)) / (0.01 * 100)    # per 1% rate move
```

We rebuild the tree with bumped parameters. This is 2 extra full tree solves per option — slow but correct. Performance optimization (reusing a baseline tree) is deferred to Phase 8.

- [ ] **Step 1: Write failing test**

Append to `describe ".calculate"`:

```ruby
it "computes vega close to Black-Scholes equivalent" do
  g = described_class.calculate(**hull_inputs)
  expect(g.vega).to be_within(0.005).of(0.37524)
end

it "computes rho close to Black-Scholes equivalent" do
  g = described_class.calculate(**hull_inputs)
  expect(g.rho).to be_within(0.01).of(0.53232)
end
```

- [ ] **Step 2: Run, expect failure**

- [ ] **Step 3: Implement bumped pricing**

Replace `vega: 0.0,` and `rho: 0.0,` lines in `calculate` with full implementations. Replace the entire `calculate` method body, after the gamma computation, with:

```ruby
  # Bump vol for vega (per 1% move)
  bumped_vol_params = tree_parameters(
    time_to_expiry: time_to_expiry,
    steps: steps,
    implied_volatility: implied_volatility + 0.01,
    risk_free_rate: risk_free_rate,
    dividend_yield: dividend_yield
  )
  price_vol_up = backward_induct_with_intermediates(type, strike, underlying_price, steps, bumped_vol_params)[:price]
  vega = (price_vol_up - price) / (0.01 * 100.0)

  # Bump rate for rho (per 1% move)
  bumped_rate_params = tree_parameters(
    time_to_expiry: time_to_expiry,
    steps: steps,
    implied_volatility: implied_volatility,
    risk_free_rate: risk_free_rate + 0.01,
    dividend_yield: dividend_yield
  )
  price_rate_up = backward_induct_with_intermediates(type, strike, underlying_price, steps, bumped_rate_params)[:price]
  rho = (price_rate_up - price) / (0.01 * 100.0)

  PureGreeks::Greeks.new(
    delta: delta,
    gamma: gamma,
    theta: (v_step2[1] - price) / (2.0 * params[:dt]) / 365.0,
    vega: vega,
    rho: rho,
    price: price,
    model: :crr_binomial_american
  )
end
```

(Replace the existing `PureGreeks::Greeks.new(...)` block at the end of `calculate`.)

- [ ] **Step 4: Run, expect pass**

Run: `bundle exec rspec spec/engines/crr_binomial_american_spec.rb`
Expected: 7 examples, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/pure_greeks/engines/crr_binomial_american.rb spec/engines/crr_binomial_american_spec.rb
git commit -m "feat: add finite-difference vega and rho to CRR engine"
```

---

## Phase 4: Intrinsic Engine + Fallback Chain

### Task 15: Intrinsic engine

**Files:**
- Create: `lib/pure_greeks/engines/intrinsic.rb`
- Test: `spec/engines/intrinsic_spec.rb`

For zero/negative IV. Returns intrinsic value, binary delta, zeros elsewhere.

- [ ] **Step 1: Write failing tests**

Create `spec/engines/intrinsic_spec.rb`:

```ruby
require "pure_greeks/engines/intrinsic"

RSpec.describe PureGreeks::Engines::Intrinsic do
  describe ".calculate" do
    it "in-the-money call: intrinsic = spot - strike, delta = 1" do
      g = described_class.calculate(type: :call, strike: 100.0, underlying_price: 110.0)
      expect(g.price).to eq(10.0)
      expect(g.delta).to eq(1.0)
      expect(g.gamma).to eq(0.0)
      expect(g.model).to eq(:intrinsic)
    end

    it "out-of-the-money call: intrinsic = 0, delta = 0" do
      g = described_class.calculate(type: :call, strike: 100.0, underlying_price: 90.0)
      expect(g.price).to eq(0.0)
      expect(g.delta).to eq(0.0)
    end

    it "in-the-money put: intrinsic = strike - spot, delta = -1" do
      g = described_class.calculate(type: :put, strike: 100.0, underlying_price: 90.0)
      expect(g.price).to eq(10.0)
      expect(g.delta).to eq(-1.0)
    end

    it "out-of-the-money put: intrinsic = 0, delta = 0" do
      g = described_class.calculate(type: :put, strike: 100.0, underlying_price: 110.0)
      expect(g.price).to eq(0.0)
      expect(g.delta).to eq(0.0)
    end
  end
end
```

- [ ] **Step 2: Run, expect failure**

Run: `bundle exec rspec spec/engines/intrinsic_spec.rb`
Expected: LoadError.

- [ ] **Step 3: Implement**

Create `lib/pure_greeks/engines/intrinsic.rb`:

```ruby
require "pure_greeks/greeks"

module PureGreeks
  module Engines
    module Intrinsic
      module_function

      def calculate(type:, strike:, underlying_price:)
        if type == :call
          price = [0.0, underlying_price - strike].max
          delta = underlying_price > strike ? 1.0 : 0.0
        else
          price = [0.0, strike - underlying_price].max
          delta = underlying_price < strike ? -1.0 : 0.0
        end

        Greeks.new(
          delta: delta,
          gamma: 0.0,
          theta: 0.0,
          vega: 0.0,
          rho: 0.0,
          price: price,
          model: :intrinsic
        )
      end
    end
  end
end
```

- [ ] **Step 4: Run, expect pass**

Run: `bundle exec rspec spec/engines/intrinsic_spec.rb`
Expected: 4 examples, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/pure_greeks/engines/intrinsic.rb spec/engines/intrinsic_spec.rb
git commit -m "feat: add intrinsic value engine for zero/negative IV"
```

### Task 16: Fallback chain orchestrator

**Files:**
- Create: `lib/pure_greeks/engines/fallback_chain.rb`
- Test: `spec/engines/fallback_chain_spec.rb`

Replicates the Tenor 3-tier order. American-exercise options try CRR Binomial first; European options skip directly to Black-Scholes. Both fall back to BS European, then Intrinsic.

- [ ] **Step 1: Write failing tests**

Create `spec/engines/fallback_chain_spec.rb`:

```ruby
require "pure_greeks/engines/fallback_chain"

RSpec.describe PureGreeks::Engines::FallbackChain do
  let(:base_inputs) do
    {
      type: :call,
      strike: 100.0,
      underlying_price: 100.0,
      time_to_expiry: 1.0,
      implied_volatility: 0.20,
      risk_free_rate: 0.05,
      dividend_yield: 0.0
    }
  end

  describe ".calculate" do
    it "uses CRR for American exercise style" do
      g = described_class.calculate(exercise_style: :american, **base_inputs)
      expect(g.model).to eq(:crr_binomial_american)
    end

    it "uses BS European for European exercise style" do
      g = described_class.calculate(exercise_style: :european, **base_inputs)
      expect(g.model).to eq(:black_scholes_european)
    end

    it "falls back to intrinsic when IV <= 0" do
      g = described_class.calculate(exercise_style: :american, **base_inputs.merge(implied_volatility: 0.0))
      expect(g.model).to eq(:intrinsic)
    end

    it "falls back to BS European when CRR raises" do
      allow(PureGreeks::Engines::CrrBinomialAmerican).to receive(:calculate).and_raise("simulated CRR failure")
      g = described_class.calculate(exercise_style: :american, **base_inputs)
      expect(g.model).to eq(:black_scholes_european)
    end

    it "falls back to intrinsic when both CRR and BS raise" do
      allow(PureGreeks::Engines::CrrBinomialAmerican).to receive(:calculate).and_raise("simulated CRR failure")
      allow(PureGreeks::Engines::BlackScholesEuropean).to receive(:calculate).and_raise("simulated BS failure")
      g = described_class.calculate(exercise_style: :american, **base_inputs)
      expect(g.model).to eq(:intrinsic)
    end
  end
end
```

- [ ] **Step 2: Run, expect failure**

Run: `bundle exec rspec spec/engines/fallback_chain_spec.rb`
Expected: LoadError.

- [ ] **Step 3: Implement**

Create `lib/pure_greeks/engines/fallback_chain.rb`:

```ruby
require "pure_greeks/engines/black_scholes_european"
require "pure_greeks/engines/crr_binomial_american"
require "pure_greeks/engines/intrinsic"

module PureGreeks
  module Engines
    module FallbackChain
      module_function

      def calculate(exercise_style:, type:, strike:, underlying_price:, time_to_expiry:, implied_volatility:, risk_free_rate:, dividend_yield:)
        if implied_volatility <= 0.0
          return Intrinsic.calculate(type: type, strike: strike, underlying_price: underlying_price)
        end

        engine_args = {
          type: type,
          strike: strike,
          underlying_price: underlying_price,
          time_to_expiry: time_to_expiry,
          implied_volatility: implied_volatility,
          risk_free_rate: risk_free_rate,
          dividend_yield: dividend_yield
        }

        if exercise_style == :american
          begin
            return CrrBinomialAmerican.calculate(**engine_args)
          rescue StandardError
            # fall through to BS
          end
        end

        begin
          return BlackScholesEuropean.calculate(**engine_args)
        rescue StandardError
          # fall through to intrinsic
        end

        Intrinsic.calculate(type: type, strike: strike, underlying_price: underlying_price)
      end
    end
  end
end
```

- [ ] **Step 4: Run, expect pass**

Run: `bundle exec rspec spec/engines/fallback_chain_spec.rb`
Expected: 5 examples, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/pure_greeks/engines/fallback_chain.rb spec/engines/fallback_chain_spec.rb
git commit -m "feat: add fallback chain orchestrator (American → European → Intrinsic)"
```

---

## Phase 5: Public OO API

### Task 17: Option class — input validation + lazy Greeks

**Files:**
- Create: `lib/pure_greeks/option.rb`
- Modify: `lib/pure_greeks.rb`
- Test: `spec/option_spec.rb`

The public OO entry. Validates inputs, computes time-to-expiry from dates, lazily delegates to `FallbackChain`, caches the Greeks struct.

- [ ] **Step 1: Write failing tests**

Create `spec/option_spec.rb`:

```ruby
require "pure_greeks"

RSpec.describe PureGreeks::Option do
  let(:valuation_date) { Date.new(2026, 4, 26) }
  let(:expiration) { Date.new(2027, 4, 26) }
  let(:base_args) do
    {
      exercise_style: :american,
      type: :call,
      strike: 100.0,
      expiration: expiration,
      underlying_price: 100.0,
      implied_volatility: 0.20,
      risk_free_rate: 0.05,
      dividend_yield: 0.0,
      valuation_date: valuation_date
    }
  end

  describe "#initialize" do
    it "accepts valid inputs" do
      expect { described_class.new(**base_args) }.not_to raise_error
    end

    it "rejects invalid exercise_style" do
      expect { described_class.new(**base_args.merge(exercise_style: :bermudan)) }
        .to raise_error(PureGreeks::InvalidInputError, /exercise_style/)
    end

    it "rejects invalid type" do
      expect { described_class.new(**base_args.merge(type: :spread)) }
        .to raise_error(PureGreeks::InvalidInputError, /type/)
    end

    it "rejects negative strike" do
      expect { described_class.new(**base_args.merge(strike: -1.0)) }
        .to raise_error(PureGreeks::InvalidInputError)
    end

    it "rejects negative spot" do
      expect { described_class.new(**base_args.merge(underlying_price: 0)) }
        .to raise_error(PureGreeks::InvalidInputError)
    end

    it "rejects expired contract" do
      expect { described_class.new(**base_args.merge(expiration: valuation_date - 1)) }
        .to raise_error(PureGreeks::ExpiredContractError)
    end
  end

  describe "Greeks accessors" do
    subject(:option) { described_class.new(**base_args) }

    it "exposes price, delta, gamma, theta, vega, rho" do
      expect(option.price).to be > 0
      expect(option.delta).to be_within(0.005).of(0.6368)
      expect(option.gamma).to be_within(0.001).of(0.01876)
      expect(option.theta).to be < 0
      expect(option.vega).to be > 0
    end

    it "exposes greeks struct" do
      expect(option.greeks).to be_a(PureGreeks::Greeks)
    end

    it "caches the greeks computation" do
      expect(PureGreeks::Engines::FallbackChain).to receive(:calculate).once.and_call_original
      option.delta
      option.gamma
      option.greeks
    end

    it "exposes calculation_model" do
      expect(option.calculation_model).to eq(:crr_binomial_american)
    end
  end
end
```

- [ ] **Step 2: Run, expect failure**

Run: `bundle exec rspec spec/option_spec.rb`
Expected: LoadError or NameError on `PureGreeks::Option`.

- [ ] **Step 3: Implement Option class**

Create `lib/pure_greeks/option.rb`:

```ruby
require "date"
require "pure_greeks/errors"
require "pure_greeks/engines/fallback_chain"

module PureGreeks
  class Option
    VALID_EXERCISE_STYLES = %i[american european].freeze
    VALID_TYPES = %i[call put].freeze
    DAYS_PER_YEAR = 365.0

    attr_reader :exercise_style, :type, :strike, :expiration, :underlying_price,
                :implied_volatility, :risk_free_rate, :dividend_yield, :valuation_date

    def initialize(exercise_style:, type:, strike:, expiration:, underlying_price:, risk_free_rate:, dividend_yield:, valuation_date:, implied_volatility: nil, market_price: nil)
      validate!(exercise_style, type, strike, underlying_price, expiration, valuation_date)

      @exercise_style = exercise_style
      @type = type
      @strike = strike.to_f
      @expiration = expiration
      @underlying_price = underlying_price.to_f
      @implied_volatility = implied_volatility&.to_f
      @market_price = market_price&.to_f
      @risk_free_rate = risk_free_rate.to_f
      @dividend_yield = dividend_yield.to_f
      @valuation_date = valuation_date
    end

    def time_to_expiry
      (@expiration - @valuation_date).to_f / DAYS_PER_YEAR
    end

    def greeks
      @greeks ||= compute_greeks
    end

    def price
      greeks.price
    end

    def delta
      greeks.delta
    end

    def gamma
      greeks.gamma
    end

    def theta
      greeks.theta
    end

    def vega
      greeks.vega
    end

    def rho
      greeks.rho
    end

    def calculation_model
      greeks.model
    end

    private

    def compute_greeks
      Engines::FallbackChain.calculate(
        exercise_style: @exercise_style,
        type: @type,
        strike: @strike,
        underlying_price: @underlying_price,
        time_to_expiry: time_to_expiry,
        implied_volatility: @implied_volatility,
        risk_free_rate: @risk_free_rate,
        dividend_yield: @dividend_yield
      )
    end

    def validate!(exercise_style, type, strike, spot, expiration, valuation_date)
      raise InvalidInputError, "exercise_style must be one of #{VALID_EXERCISE_STYLES}" unless VALID_EXERCISE_STYLES.include?(exercise_style)
      raise InvalidInputError, "type must be one of #{VALID_TYPES}" unless VALID_TYPES.include?(type)
      raise InvalidInputError, "strike must be positive" unless strike.is_a?(Numeric) && strike > 0
      raise InvalidInputError, "underlying_price must be positive" unless spot.is_a?(Numeric) && spot > 0
      raise ExpiredContractError, "contract expired on #{expiration}" if expiration <= valuation_date
    end
  end
end
```

- [ ] **Step 4: Update top-level require**

Modify `lib/pure_greeks.rb` to require the public surface:

```ruby
require "pure_greeks/version"
require "pure_greeks/errors"
require "pure_greeks/greeks"
require "pure_greeks/option"

module PureGreeks
end
```

- [ ] **Step 5: Run, expect pass**

Run: `bundle exec rspec spec/option_spec.rb`
Expected: 11 examples, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add lib/pure_greeks/option.rb lib/pure_greeks.rb spec/option_spec.rb
git commit -m "feat: add Option public API with input validation and caching"
```

---

## Phase 6: Implied Volatility Solver

### Task 18: Brent's method root finder

**Files:**
- Create: `lib/pure_greeks/implied_volatility/brent_solver.rb`
- Test: `spec/implied_volatility/brent_solver_spec.rb`

Brent's method is robust (combines bisection guarantee with secant/inverse-quadratic speed). Reference: Numerical Recipes ch. 9.3, or Wikipedia's pseudocode. We implement a generic 1D root finder, then layer the price-inversion logic on top in Task 19.

- [ ] **Step 1: Write failing tests**

Create `spec/implied_volatility/brent_solver_spec.rb`:

```ruby
require "pure_greeks/implied_volatility/brent_solver"

RSpec.describe PureGreeks::ImpliedVolatility::BrentSolver do
  describe ".find_root" do
    it "finds root of x^2 - 4 in [1, 3] (= 2.0)" do
      root = described_class.find_root(lower: 1.0, upper: 3.0, tolerance: 1e-9) { |x| x**2 - 4.0 }
      expect(root).to be_within(1e-9).of(2.0)
    end

    it "finds root of cos(x) - x near 0.7390851" do
      root = described_class.find_root(lower: 0.0, upper: 1.0, tolerance: 1e-9) { |x| ::Math.cos(x) - x }
      expect(root).to be_within(1e-9).of(0.7390851332151607)
    end

    it "raises if root is not bracketed" do
      expect {
        described_class.find_root(lower: 5.0, upper: 10.0, tolerance: 1e-6) { |x| x**2 - 4.0 }
      }.to raise_error(PureGreeks::IVConvergenceError, /not bracketed/)
    end
  end
end
```

- [ ] **Step 2: Run, expect failure**

Run: `bundle exec rspec spec/implied_volatility/brent_solver_spec.rb`
Expected: LoadError.

- [ ] **Step 3: Implement Brent's method**

Create `lib/pure_greeks/implied_volatility/brent_solver.rb`:

```ruby
require "pure_greeks/errors"

module PureGreeks
  module ImpliedVolatility
    module BrentSolver
      MAX_ITERATIONS = 100

      module_function

      def find_root(lower:, upper:, tolerance: 1e-8, &f)
        a = lower.to_f
        b = upper.to_f
        fa = f.call(a)
        fb = f.call(b)

        raise IVConvergenceError, "root not bracketed: f(#{a})=#{fa}, f(#{b})=#{fb}" if fa * fb > 0

        if fa.abs < fb.abs
          a, b = b, a
          fa, fb = fb, fa
        end

        c = a
        fc = fa
        mflag = true
        d = nil

        MAX_ITERATIONS.times do
          return b if fb.abs < tolerance || (b - a).abs < tolerance

          s =
            if fa != fc && fb != fc
              # Inverse quadratic interpolation
              a * fb * fc / ((fa - fb) * (fa - fc)) +
                b * fa * fc / ((fb - fa) * (fb - fc)) +
                c * fa * fb / ((fc - fa) * (fc - fb))
            else
              # Secant method
              b - fb * (b - a) / (fb - fa)
            end

          condition1 = !s.between?([(3 * a + b) / 4, b].min, [(3 * a + b) / 4, b].max)
          condition2 = mflag && (s - b).abs >= (b - c).abs / 2
          condition3 = !mflag && (s - b).abs >= (c - d).abs / 2
          condition4 = mflag && (b - c).abs < tolerance
          condition5 = !mflag && d && (c - d).abs < tolerance

          if condition1 || condition2 || condition3 || condition4 || condition5
            s = (a + b) / 2.0
            mflag = true
          else
            mflag = false
          end

          fs = f.call(s)
          d = c
          c = b
          fc = fb

          if fa * fs < 0
            b = s
            fb = fs
          else
            a = s
            fa = fs
          end

          if fa.abs < fb.abs
            a, b = b, a
            fa, fb = fb, fa
          end
        end

        raise IVConvergenceError, "exceeded #{MAX_ITERATIONS} iterations"
      end
    end
  end
end
```

- [ ] **Step 4: Run, expect pass**

Run: `bundle exec rspec spec/implied_volatility/brent_solver_spec.rb`
Expected: 3 examples, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/pure_greeks/implied_volatility/brent_solver.rb spec/implied_volatility/brent_solver_spec.rb
git commit -m "feat: add Brent's method root finder"
```

### Task 19: Implied volatility on Option

**Files:**
- Modify: `lib/pure_greeks/option.rb`
- Modify: `spec/option_spec.rb`

Inverts the BS European pricing function via Brent. (American IV solving via CRR is too slow for v0.1 — use BS European inversion as a close approximation. Document this limitation.)

- [ ] **Step 1: Write failing test**

Append to `spec/option_spec.rb`:

```ruby
describe "#implied_volatility (when market_price given)" do
  let(:european_args) do
    {
      exercise_style: :european,
      type: :call,
      strike: 100.0,
      expiration: expiration,
      underlying_price: 100.0,
      market_price: 10.4506,
      risk_free_rate: 0.05,
      dividend_yield: 0.0,
      valuation_date: valuation_date
    }
  end

  it "solves IV ≈ 0.20 for known Hull price" do
    option = described_class.new(**european_args)
    expect(option.implied_volatility).to be_within(1e-4).of(0.20)
  end

  it "raises when market_price absent and no IV given" do
    args = european_args.dup
    args.delete(:market_price)
    option = described_class.new(**args)
    expect { option.implied_volatility }.to raise_error(PureGreeks::InvalidInputError)
  end
end
```

- [ ] **Step 2: Run, expect failure**

Run: `bundle exec rspec spec/option_spec.rb`
Expected: NoMethodError on `implied_volatility` (currently only an attr).

- [ ] **Step 3: Implement IV solver on Option**

Modify `lib/pure_greeks/option.rb`. Add to top of file:

```ruby
require "pure_greeks/engines/black_scholes_european"
require "pure_greeks/implied_volatility/brent_solver"
```

Replace the `def implied_volatility` accessor (currently `attr_reader`) by removing it from the `attr_reader` line and adding:

```ruby
def implied_volatility
  return @implied_volatility if @implied_volatility
  raise InvalidInputError, "market_price required to solve for implied_volatility" unless @market_price

  @implied_volatility = ImpliedVolatility::BrentSolver.find_root(lower: 1e-6, upper: 5.0, tolerance: 1e-6) do |sigma|
    Engines::BlackScholesEuropean.price(
      type: @type,
      strike: @strike,
      underlying_price: @underlying_price,
      time_to_expiry: time_to_expiry,
      implied_volatility: sigma,
      risk_free_rate: @risk_free_rate,
      dividend_yield: @dividend_yield
    ) - @market_price
  end
end
```

(Update the `attr_reader` line to remove `:implied_volatility`.)

- [ ] **Step 4: Run, expect pass**

Run: `bundle exec rspec spec/option_spec.rb`
Expected: 13 examples, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/pure_greeks/option.rb spec/option_spec.rb
git commit -m "feat: add implied volatility solver via Brent's method"
```

---

## Phase 7: Validation Against Tenor Golden Dataset

> **Prereq:** Tenor's `mcp__postgres-prod__query` MCP tool must be available in this session. The Tenor user memory at `~/.claude/projects/-Users-jravaliya-Code-tenor/memory/MEMORY.md` confirms read-only MCP access is the default. Per `feedback_prod_db_writes.md`, **only SELECT queries** — never any write.
>
> If MCP unavailable, skip this phase, leave `spec/regression/fixtures/tenor_golden.json` empty, and note in the README that golden-dataset validation is pending.

### Task 20: Export tool — pull golden data from Tenor prod DB

**Files:**
- Create: `tools/golden_dataset_export.rb`
- Create: `spec/regression/fixtures/tenor_golden.json`

The export script is **a one-shot manual run**, not part of the gem's runtime. It documents the SQL query used so future regenerations are reproducible.

**Connecting to Tenor's DB.** The connection string lives in `~/Code/tenor/.mcp.json` under `mcpServers.postgres-prod.args[2]`. Read it directly and pipe it into `psql`:

```bash
PG_URL=$(jq -r '.mcpServers."postgres-prod".args[2]' ~/Code/tenor/.mcp.json)
psql "$PG_URL" -c "\d options.snapshots"   # smoke-test: should describe table
```

This is read-only — only run `SELECT` statements. The MCP path (`mcp__postgres-prod__query`) is also fine if it's wired into the current session, but `psql` works with no MCP setup.

**Risk-free rate sourcing.** Before writing the export, run `\d options.snapshots` (and any related rate/config tables) to see whether Tenor stores the rate per-snapshot. Three cases:

1. **Stored per-snapshot** (most likely): include the rate column directly in the `SELECT` below. Done.
2. **Stored as a constant in Tenor config**: read the constant from Tenor's source, embed it in every fixture row, document the value in the fixture's `_meta` block.
3. **Computed at run-time from FRED**: pull the FRED CSV for the matching snapshot dates — `https://fred.stlouisfed.org/graph/fredgraph.csv?id=DGS3MO` (or whichever series Tenor uses; check Tenor's source). No FRED API key needed for the CSV endpoint. Embed per-row in the fixture.

The existing query below assumes case (1) and pulls a `risk_free_rate` column. Adjust if the schema differs.

- [ ] **Step 1: Write the export script**

Create `tools/golden_dataset_export.rb`:

```ruby
# frozen_string_literal: true

# Manual one-shot tool to export a golden dataset from Tenor's prod DB.
#
# This script is not run as part of the gem; it documents the query and the
# expected JSON shape. To regenerate the fixture, run the SQL below via
# Tenor's mcp__postgres-prod__query MCP and pipe the output into
# spec/regression/fixtures/tenor_golden.json.
#
# READ-ONLY. Never modify this query to a write operation.

GOLDEN_DATASET_QUERY = <<~SQL
  SELECT
    s.id AS snapshot_id,
    s.option_type,
    s.strike,
    s.expiration,
    s.underlying_price,
    s.implied_volatility,
    s.snapshot_date,
    COALESCE(s.dividend_yield, 0) AS dividend_yield,
    s.risk_free_rate,  -- adjust if Tenor stores this elsewhere; see notes above Step 1
    g.delta,
    g.gamma,
    g.theta,
    g.vega,
    g.rho,
    g.calculated_price,
    g.calculation_model
  FROM options.greeks g
  JOIN options.snapshots s ON s.id = g.snapshot_id
  WHERE g.calculation_model IN ('quantlib_american', 'quantlib_european', 'intrinsic')
    AND s.implied_volatility IS NOT NULL
    AND s.implied_volatility > 0
    AND s.expiration > s.snapshot_date
  ORDER BY RANDOM()
  LIMIT 500;
SQL

# If Tenor stores risk-free rate per-snapshot, the SELECT above pulls it
# directly. If it's a constant or pulled from FRED, see the prose notes
# above Step 1 for the FRED CSV fallback. Use this constant only as a
# last resort.
DEFAULT_RISK_FREE_RATE = 0.05

puts GOLDEN_DATASET_QUERY
puts "(Pipe the result into JSON shaped like:)"
puts <<~JSON
  [
    {
      "snapshot_id": "...",
      "option_type": "calls",
      "strike": 150.0,
      "expiration": "2026-06-19",
      "underlying_price": 148.5,
      "implied_volatility": 0.35,
      "snapshot_date": "2026-04-26",
      "dividend_yield": 0.0,
      "risk_free_rate": 0.05,
      "expected": {
        "delta": 0.42,
        "gamma": 0.018,
        "theta": -0.012,
        "vega": 0.31,
        "rho": 0.08,
        "calculated_price": 4.27,
        "calculation_model": "quantlib_american"
      }
    }
  ]
JSON
```

- [ ] **Step 2: Inspect schema and confirm rate sourcing**

```bash
PG_URL=$(jq -r '.mcpServers."postgres-prod".args[2]' ~/Code/tenor/.mcp.json)
psql "$PG_URL" -c "\d options.snapshots"
psql "$PG_URL" -c "\d options.greeks"
```

If `risk_free_rate` is on `options.snapshots`, proceed with the query as-is. If it's elsewhere, adjust the SELECT. If Tenor pulls live from FRED, switch to the FRED CSV approach and document the series ID in the fixture's `_meta`.

- [ ] **Step 3: Run the export**

```bash
psql "$PG_URL" -A -F $'\t' --pset=footer=off -c "<contents of GOLDEN_DATASET_QUERY>" > /tmp/tenor_golden.tsv
```

(Or use the MCP path `mcp__postgres-prod__query` if it's wired up — same result.)

- [ ] **Step 4: Write fixture**

Transform the TSV/MCP result into the JSON shape shown in step 1, save to `spec/regression/fixtures/tenor_golden.json`. Include a top-level `_meta` block recording the export date, source DB, and rate-sourcing decision (per-snapshot column / Tenor constant / FRED series ID).

- [ ] **Step 5: Commit**

```bash
git add tools/golden_dataset_export.rb spec/regression/fixtures/tenor_golden.json
git commit -m "feat: add Tenor golden dataset export tool and fixture"
```

### Task 21: Regression suite

**Files:**
- Create: `spec/regression/golden_dataset_spec.rb`

Compares PureGreeks output against QuantLib outputs from the fixture. Reports drift, fails on tolerance violation.

- [ ] **Step 1: Write the regression spec**

Create `spec/regression/golden_dataset_spec.rb`:

```ruby
require "json"
require "date"
require "pure_greeks"

RSpec.describe "Regression against Tenor QuantLib golden dataset" do
  fixture_path = File.expand_path("fixtures/tenor_golden.json", __dir__)

  if File.exist?(fixture_path)
    fixture = JSON.parse(File.read(fixture_path))

    fixture.each do |row|
      describe "snapshot #{row['snapshot_id']}" do
        let(:expected) { row.fetch("expected") }
        let(:option) do
          PureGreeks::Option.new(
            exercise_style: :american,
            type: row["option_type"] == "puts" ? :put : :call,
            strike: row["strike"].to_f,
            expiration: Date.parse(row["expiration"]),
            underlying_price: row["underlying_price"].to_f,
            implied_volatility: row["implied_volatility"].to_f,
            risk_free_rate: row["risk_free_rate"].to_f,
            dividend_yield: row["dividend_yield"].to_f,
            valuation_date: Date.parse(row["snapshot_date"])
          )
        end

        it "matches delta within 1e-3" do
          expect(option.delta).to be_within(1e-3).of(expected["delta"].to_f)
        end

        it "matches gamma within 1e-4" do
          expect(option.gamma).to be_within(1e-4).of(expected["gamma"].to_f)
        end

        it "matches theta within 1e-3" do
          expect(option.theta).to be_within(1e-3).of(expected["theta"].to_f)
        end

        it "matches vega within 1e-3" do
          expect(option.vega).to be_within(1e-3).of(expected["vega"].to_f)
        end

        it "matches rho within 5e-3" do
          expect(option.rho).to be_within(5e-3).of(expected["rho"].to_f)
        end

        it "matches price within 1e-2" do
          expect(option.price).to be_within(1e-2).of(expected["calculated_price"].to_f)
        end
      end
    end
  else
    it "skipped: golden fixture not present" do
      pending "spec/regression/fixtures/tenor_golden.json missing — run tools/golden_dataset_export.rb"
      raise
    end
  end
end
```

- [ ] **Step 2: Run regression suite**

Run: `bundle exec rspec spec/regression/golden_dataset_spec.rb`

Two outcomes are acceptable:

**A) All pass** — celebrate, commit, move on.

**B) Some fail** — investigate. Tighten/loosen tolerances based on observed drift. Document drift in a `REGRESSION_REPORT.md` at the repo root with histograms (max/mean/std drift per Greek). The goal is `< 0.5%` of fixture rows failing — if more, debug the math.

- [ ] **Step 3: Iterate until passing**

If failures point to a math bug, fix the engine. If failures are extreme-IV edge cases that QuantLib also handles via fallback, ensure your fallback chain agrees.

- [ ] **Step 4: Commit**

```bash
git add spec/regression/golden_dataset_spec.rb REGRESSION_REPORT.md
git commit -m "test: add regression suite against Tenor QuantLib golden dataset"
```

---

## Phase 8: Performance

### Task 22: Single-option microbenchmark

**Files:**
- Create: `bench/single_option.rb`

- [ ] **Step 1: Write benchmark**

Create `bench/single_option.rb`:

```ruby
require "benchmark/ips"
require "pure_greeks"

option_args = {
  exercise_style: :american,
  type: :call,
  strike: 150.0,
  expiration: Date.new(2027, 4, 26),
  underlying_price: 148.5,
  implied_volatility: 0.35,
  risk_free_rate: 0.05,
  dividend_yield: 0.0,
  valuation_date: Date.new(2026, 4, 26)
}

Benchmark.ips do |x|
  x.report("American CRR (200 steps)") do
    PureGreeks::Option.new(**option_args).greeks
  end

  x.report("European Black-Scholes") do
    PureGreeks::Option.new(**option_args.merge(exercise_style: :european)).greeks
  end
end
```

- [ ] **Step 2: Add benchmark-ips dev dep**

Edit `pure_greeks.gemspec`:

```ruby
spec.add_development_dependency "benchmark-ips", "~> 2.13"
```

Run: `bundle install`

- [ ] **Step 3: Run benchmark, record baseline**

Run: `bundle exec ruby bench/single_option.rb`

Expected output (rough order of magnitude — actual numbers depend on hardware):
- BS European: ~10,000-50,000 ops/sec
- CRR American: ~50-500 ops/sec (the 200-step tree dominates)

Save the output to `BENCHMARKS.md` at the repo root.

- [ ] **Step 4: Commit**

```bash
git add bench/single_option.rb pure_greeks.gemspec Gemfile.lock BENCHMARKS.md
git commit -m "perf: add single-option microbenchmark and baseline"
```

### Task 23: Batch benchmark

**Files:**
- Create: `bench/batch.rb`

- [ ] **Step 1: Write batch benchmark**

Create `bench/batch.rb`:

```ruby
require "benchmark"
require "pure_greeks"

base_args = {
  exercise_style: :american,
  strike: 150.0,
  expiration: Date.new(2027, 4, 26),
  underlying_price: 148.5,
  risk_free_rate: 0.05,
  dividend_yield: 0.0,
  valuation_date: Date.new(2026, 4, 26)
}

[100, 1_000, 10_000].each do |n|
  options = Array.new(n) do |i|
    PureGreeks::Option.new(
      type: i.even? ? :call : :put,
      implied_volatility: 0.20 + (i % 10) * 0.05,
      **base_args
    )
  end

  elapsed = Benchmark.realtime do
    options.each(&:greeks)
  end

  puts "#{n} options: #{elapsed.round(3)}s — #{(n / elapsed).round} ops/sec"
end
```

- [ ] **Step 2: Run, record results**

Run: `bundle exec ruby bench/batch.rb`

Append results to `BENCHMARKS.md`.

- [ ] **Step 3: Decision point — is performance acceptable?**

Compare to Tenor's QuantLib baseline. The Tenor `GreeksCalculationBatchJob` processes ~5,000-15,000 options per batch in ~30-60s (~250 ops/sec). If pure-Ruby PureGreeks hits ≥50% of that throughput (~125 ops/sec), ship v0.1 as pure Ruby.

If throughput < 50 ops/sec for American options, consider these in v0.2:
1. Drop default `steps` from 200 → 100 (loses some accuracy in extreme cases — verify against golden dataset).
2. Native C extension for the binomial backward induction loop (the inner `(0..i).each` is the hot path). Use `rice` gem.
3. SIMD via `numo-narray` for vectorized backward induction.

Document the chosen path in `BENCHMARKS.md` under a "Path to v0.2" section.

- [ ] **Step 4: Commit**

```bash
git add bench/batch.rb BENCHMARKS.md
git commit -m "perf: add batch benchmark and v0.2 performance plan"
```

---

## Phase 9: Documentation & Release

### Task 24: README (developer-focused)

**Files:**
- Modify: `README.md`

The README is for developers who want to install, contribute to, or release the gem. End-user usage docs live on the GitHub Pages site (Task 27). The README should be short and scannable.

- [ ] **Step 1: Write README**

Replace `README.md` with:

```markdown
# pure_greeks

[![Gem Version](https://badge.fury.io/rb/pure_greeks.svg)](https://rubygems.org/gems/pure_greeks)
[![CI](https://github.com/jayrav13/ruby-pure-greeks/actions/workflows/ci.yml/badge.svg)](https://github.com/jayrav13/ruby-pure-greeks/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Pure-Ruby options Greeks (delta, gamma, theta, vega, rho), pricing, and implied volatility for vanilla European and American options. No Python, no QuantLib system dep, no native code.

**Documentation, examples, and engine internals: https://jayrav13.github.io/ruby-pure-greeks/**

## Installation

Add to your Gemfile:

```ruby
gem "pure_greeks"
```

Then `bundle install`. Or install directly:

```bash
gem install pure_greeks
```

Requires Ruby 3.2 or newer. No system dependencies.

## Quick example

```ruby
require "pure_greeks"

option = PureGreeks::Option.new(
  exercise_style: :american, type: :call,
  strike: 150.0, expiration: Date.new(2026, 6, 19),
  underlying_price: 148.5, implied_volatility: 0.35,
  risk_free_rate: 0.05, dividend_yield: 0.0,
  valuation_date: Date.today
)

option.price   # => 4.27
option.delta   # => 0.42
```

For the full API, the implied-volatility solver, how the three engines fall back to one another, validation methodology, and limitations, see the [documentation site](https://jayrav13.github.io/ruby-pure-greeks/).

## Development

Clone and bootstrap:

```bash
git clone https://github.com/jayrav13/ruby-pure-greeks.git
cd pure_greeks
bin/setup
```

Run the test suite:

```bash
bundle exec rspec
```

Run the linter:

```bash
bundle exec rubocop
```

Open a console with the gem loaded:

```bash
bin/console
```

To install this gem onto your local machine for trial use:

```bash
bundle exec rake install
```

## Releasing

Releases are tag-driven through CI — no manual `gem push` needed.

1. On a feature branch, bump `lib/pure_greeks/version.rb` to the new version.
2. Add a section to `CHANGELOG.md` for the new version (Keep-a-Changelog format).
3. Open a PR; CI must be green.
4. Merge to `main`. The release workflow (`.github/workflows/release.yml`) detects the version bump, runs the test suite, builds the gem, publishes to RubyGems via [Trusted Publishing](https://guides.rubygems.org/trusted-publishing/) (no API key), creates a `vX.Y.Z` git tag, and opens a GitHub Release with auto-generated notes from the merged PRs.

The RubyGems version badge above refreshes automatically once the new version indexes on rubygems.org (usually within a minute).

## Contributing

Bug reports and pull requests are welcome at https://github.com/jayrav13/ruby-pure-greeks. Please run `bundle exec rspec` and `bundle exec rubocop` locally before opening a PR. CI runs both on Ruby 3.2, 3.3, and 3.4.

## License

MIT. See `LICENSE.txt`.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: dev-focused README with badges, link to docs site"
```

### Task 25: CHANGELOG

**Files:**
- Create: `CHANGELOG.md`

- [ ] **Step 1: Write CHANGELOG**

Create `CHANGELOG.md`:

```markdown
# Changelog

## [0.1.0] - YYYY-MM-DD

Initial release.

- Object-oriented `PureGreeks::Option` API for vanilla American/European options.
- Three engines: CRR Binomial American (200 steps), Black-Scholes European (analytic), Intrinsic.
- Automatic engine selection with fallback chain.
- Implied volatility solver via Brent's method.
- Regression-validated against QuantLib outputs from production options data.
```

(Replace `YYYY-MM-DD` with the actual release date.)

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: add CHANGELOG"
```

### Task 26: GitHub Actions CI

**Files:**
- Modify: `.github/workflows/ci.yml` (already exists from Task 1, currently the bundler default)

Restructure CI into two parallel jobs — `lint` and `test` — and add a rubocop cache so reruns are fast. This pattern mirrors `~/Code/njtransit/.github/workflows/ci.yml`.

- [ ] **Step 1: Replace `.github/workflows/ci.yml`**

```yaml
name: CI

on:
  pull_request:
  push:
    branches: [main]

jobs:
  lint:
    runs-on: ubuntu-latest
    env:
      RUBOCOP_CACHE_ROOT: tmp/rubocop
    steps:
      - name: Checkout code
        uses: actions/checkout@v6

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true

      - name: Prepare RuboCop cache
        uses: actions/cache@v5
        env:
          DEPENDENCIES_HASH: ${{ hashFiles('.ruby-version', '**/.rubocop.yml', 'Gemfile.lock') }}
        with:
          path: ${{ env.RUBOCOP_CACHE_ROOT }}
          key: rubocop-${{ runner.os }}-${{ env.DEPENDENCIES_HASH }}-${{ github.ref_name == github.event.repository.default_branch && github.run_id || 'default' }}
          restore-keys: |
            rubocop-${{ runner.os }}-${{ env.DEPENDENCIES_HASH }}-

      - name: Lint code for consistent style
        run: bundle exec rubocop --parallel -f github

  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        ruby-version: ["3.2", "3.3", "3.4"]
    steps:
      - name: Checkout code
        uses: actions/checkout@v6

      - name: Set up Ruby ${{ matrix.ruby-version }}
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: ${{ matrix.ruby-version }}
          bundler-cache: true

      - name: Run RSpec
        run: bundle exec rspec
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: split lint/test jobs, add rubocop cache, matrix Ruby 3.2-3.4"
```

### Task 27: GitHub Pages documentation site

The README only covers dev setup. End-user usage docs — the API surface, examples, how the three engines fall back, validation methodology, and limitations — live on a GitHub Pages site served from `docs/` on `main`. We use a stock Jekyll theme (`cayman`) so there is no toolchain to maintain locally; GitHub builds the site on push.

**Files:**
- Create: `docs/_config.yml`
- Create: `docs/index.md`
- Create: `docs/usage.md`
- Create: `docs/engines.md`
- Create: `docs/validation.md`
- Create: `docs/limitations.md`

- [ ] **Step 1: Create `docs/_config.yml`**

```yaml
title: pure_greeks
description: Pure-Ruby options Greeks, pricing, and implied volatility — no QuantLib, no native code.
theme: jekyll-theme-cayman

# These two are surfaced by the cayman theme as header buttons.
github:
  repository_url: https://github.com/jayrav13/ruby-pure-greeks
  zip_url: https://github.com/jayrav13/ruby-pure-greeks/archive/refs/heads/main.zip

# Don't try to render fixtures or specs if anyone copies them in here later.
exclude:
  - "*.gem"
  - Gemfile
  - Gemfile.lock
```

- [ ] **Step 2: Create `docs/index.md`**

This is the landing page. Keep it tight; it should funnel readers to the right sub-page.

```markdown
---
title: pure_greeks
---

# pure_greeks

Pure-Ruby options Greeks (delta, gamma, theta, vega, rho), pricing, and implied volatility for vanilla European and American options. No Python dependency, no QuantLib system install, no native code.

```ruby
gem "pure_greeks"
```

## Where to go next

- **[Usage](usage.html)** — full API reference with worked examples for pricing, Greeks, and implied volatility.
- **[How the engines work](engines.html)** — Black-Scholes, CRR binomial, intrinsic, and how the fallback chain selects between them.
- **[Validation](validation.html)** — methodology and tolerances for regression-testing against QuantLib output.
- **[Limitations](limitations.html)** — what v0.1 does not cover and why.

## Source & releases

[GitHub repository](https://github.com/jayrav13/ruby-pure-greeks) · [RubyGems](https://rubygems.org/gems/pure_greeks) · [Changelog](https://github.com/jayrav13/ruby-pure-greeks/blob/main/CHANGELOG.md)
```

- [ ] **Step 3: Create `docs/usage.md`**

This page absorbs the usage examples that previously lived in the README. Move them verbatim and expand: include the IV-solver example, all five Greeks, the `calculation_model` accessor, and a note on each constructor argument.

```markdown
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

Pass `market_price:` instead of `implied_volatility:`. The solver uses Brent's method.

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
| `strike` | Numeric | |
| `expiration` | `Date` | |
| `underlying_price` | Numeric | |
| `implied_volatility` | Numeric | Annualized, decimal (0.35 == 35%). Either this or `market_price`, not both. |
| `market_price` | Numeric | Triggers the IV solver. Either this or `implied_volatility`, not both. |
| `risk_free_rate` | Numeric | Annualized, decimal. |
| `dividend_yield` | Numeric | Annualized, decimal. |
| `valuation_date` | `Date` | Defaults to `Date.today` if omitted. |

(Document any additional accessors or behavior added during implementation — keep this table in sync with `lib/pure_greeks/option.rb`.)
```

- [ ] **Step 4: Create `docs/engines.md`**

```markdown
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

## Why this exists

QuantLib is the industry-standard option pricer, but its Ruby binding is a binary dep that's painful in production: you need a system install, version pinning is fragile, and it's hard to deploy on serverless platforms. `pure_greeks` is a deliberately scoped subset — the vanilla American/European Greeks that most equity-option workloads actually need — implemented in pure Ruby so it installs anywhere `gem install` works.
```

- [ ] **Step 5: Create `docs/validation.md`**

```markdown
---
title: Validation
---

# Validation

The engines have been regression-tested against a frozen dataset of ~500 historical option snapshots whose Greeks were computed by QuantLib (CRR Binomial American, 200 steps). The fixture and the script that generates it live in `spec/regression/`.

## Tolerances

| Quantity | Absolute tolerance |
|---|---|
| Price | 1e-3 |
| Delta | 1e-3 |
| Gamma | 1e-4 |
| Theta (per calendar day) | 1e-3 |
| Vega (per 1% vol move) | 1e-3 |
| Rho (per 1% rate move) | 1e-3 |

These tolerances are tighter than the noise floor of typical market data (bid-ask spread, last-trade staleness), so any drift large enough to matter for downstream analytics will fail CI.

## How to regenerate the fixture

The fixture is regenerated manually (not on every CI run) by the on-call engineer when the source dataset changes. See `spec/regression/export_tenor_golden.rb` for the SQL query and the expected output shape. The export tool is read-only against the source database.
```

- [ ] **Step 6: Create `docs/limitations.md`**

```markdown
---
title: Limitations
---

# Limitations

`pure_greeks` v0.1 is intentionally scoped. Things it does **not** do:

- **Throughput.** Pure Ruby is roughly 10× slower than QuantLib's C++ for American options. Fine for interactive use and most batch jobs; see `BENCHMARKS.md` in the repo for measured numbers. A native extension is on the v0.2 backlog if real workloads need it.
- **American implied volatility.** The IV solver inverts the Black-Scholes European pricer even for American options. For American options with significant early-exercise premium, the solved IV will be slightly off. v0.2 may add a CRR-based IV solver (slower but exact).
- **Non-vanilla exercise.** No Bermudan, Asian, barrier, or any other exotic exercise style.
- **Discrete dividends.** Dividend yield is treated as a continuous constant. Discrete dividends require a different tree and are out of scope for v0.1.
- **Day-count conventions.** Time-to-expiry uses Actual/365 Fixed. If your reference data uses Actual/360 or 30/360, expect small drifts.

If any of these blocks your use case, please open an issue describing the workload — that drives v0.2 prioritization.
```

- [ ] **Step 7: Enable Pages in repo settings**

GitHub Pages cannot be enabled from the local clone; it must be turned on once in the GitHub UI. Tell the user (don't attempt to do it from the CLI):

> Once the repo is on GitHub: **Settings → Pages → Source: Deploy from a branch → Branch: `main` / folder: `/docs` → Save.** First build takes ~1 minute. The site URL will be `https://<OWNER>.github.io/pure_greeks/`.

No GitHub Actions workflow is needed for this — Pages auto-builds when the source is `main /docs`.

- [ ] **Step 8: Commit**

```bash
git add docs/
git commit -m "docs: GitHub Pages site for usage, engines, validation, limitations"
```

- [ ] **Step 9: Verify locally (optional)**

If the implementer wants to preview before pushing:

```bash
gem install bundler jekyll
cd docs && jekyll serve
```

Otherwise, verification happens after push by visiting the Pages URL.

### Task 28: Release automation (RubyGems Trusted Publishing + GitHub Releases)

**Files:**
- Create: `.github/workflows/release.yml`

The release flow is tag-driven by a version-file change on `main`. When `lib/pure_greeks/version.rb` changes, this workflow runs the test suite, builds the gem, publishes it to RubyGems via Trusted Publishing (OIDC — no API key in repo secrets), then creates a `vX.Y.Z` git tag and a GitHub Release with auto-generated notes from merged PRs. Mirrors `~/Code/njtransit/.github/workflows/release.yml`.

**Prerequisites the user has already handled** (per spike conversation):
- Trusted Publishing is configured on rubygems.org for this gem.
- A GitHub Environment named `rubygems` exists in the repo and is wired to the trusted publisher binding.

If either is not in place when this task runs, stop and surface that to the user — the workflow will fail-closed without them.

- [ ] **Step 1: Create `.github/workflows/release.yml`**

```yaml
name: Release

on:
  push:
    branches: [main]
    paths:
      - "lib/pure_greeks/version.rb"

jobs:
  release:
    runs-on: ubuntu-latest
    environment: rubygems
    permissions:
      contents: write
      id-token: write

    steps:
      - name: Checkout code
        uses: actions/checkout@v6

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true

      - name: Run tests
        run: bundle exec rspec

      - name: Run linter
        run: bundle exec rubocop --parallel -f github

      - name: Extract version
        id: version
        run: |
          VERSION=$(ruby -r ./lib/pure_greeks/version -e 'puts PureGreeks::VERSION')
          echo "version=$VERSION" >> "$GITHUB_OUTPUT"
          echo "tag=v$VERSION" >> "$GITHUB_OUTPUT"

      - name: Build gem
        run: gem build pure_greeks.gemspec

      - name: Configure Trusted Publishing credentials
        uses: rubygems/configure-rubygems-credentials@main

      - name: Publish to RubyGems
        run: gem push pure_greeks-${{ steps.version.outputs.version }}.gem

      - name: Create GitHub release
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          TAG: ${{ steps.version.outputs.tag }}
          GEM_FILE: pure_greeks-${{ steps.version.outputs.version }}.gem
        run: |
          gh release create "$TAG" \
            --title "$TAG" \
            --generate-notes \
            "$GEM_FILE"
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: add release workflow (RubyGems Trusted Publishing + GitHub Releases)"
```

### Task 29: Cut v0.1.0 (CI does the publish)

**Files:**
- Modify: `lib/pure_greeks/version.rb`
- Modify: `CHANGELOG.md`

This task is the trigger for the release workflow built in Task 28. The publish itself happens automatically when the merge to `main` lands.

- [ ] **Step 1: Set version**

Replace `lib/pure_greeks/version.rb` contents:

```ruby
# frozen_string_literal: true

module PureGreeks
  VERSION = "0.1.0"
end
```

- [ ] **Step 2: Date the CHANGELOG entry**

In `CHANGELOG.md`, replace `[0.1.0] - YYYY-MM-DD` with the actual release date.

- [ ] **Step 3: Verify everything passes locally**

```bash
bundle exec rspec
bundle exec rubocop
bundle exec rspec spec/regression
```

All three must be clean.

- [ ] **Step 4: Open the release PR**

```bash
git checkout -b release/v0.1.0
git add lib/pure_greeks/version.rb CHANGELOG.md
git commit -m "chore: release 0.1.0"
git push -u origin release/v0.1.0
gh pr create --title "Release v0.1.0" --body "Cuts v0.1.0. CI will publish to RubyGems and create the GitHub Release on merge."
```

- [ ] **Step 5: Confirm with user before merging**

Do **not** merge the PR autonomously. Surface to the user: "Release PR is up. CI is green. Merge to publish v0.1.0 to RubyGems and create the GitHub Release?" and wait for explicit go-ahead.

- [ ] **Step 6: After merge — watch the release workflow**

Once merged, watch:

```bash
gh run watch
```

Expected outcome (~2-3 min):
- `pure_greeks 0.1.0` is live at https://rubygems.org/gems/pure_greeks
- A `v0.1.0` GitHub Release exists at https://github.com/jayrav13/ruby-pure-greeks/releases/tag/v0.1.0 with auto-generated notes
- The RubyGems badge in the README starts resolving (may take an extra minute to index)

---

## Open Questions / Future Work

The implementing session should flag these to the user as they come up:

1. ~~**License**~~: resolved during Task 1 — MIT propagated to gemspec; `LICENSE.txt` still needs to be written before publish.
2. ~~**GitHub repo**~~: resolved — repo lives at `github.com/jayrav13/ruby-pure-greeks`. Origin is wired up.
3. **Risk-free rate source**: confirm what rate Tenor's QuantLib run used (likely a constant from config or per-snapshot from FRED). Make this explicit in the golden fixture's `_meta` block.
4. **American IV solver**: v0.1 inverts BS European. v0.2 could add CRR-based IV (slower but exact for American). Document as a known limitation.
5. **C extension trigger**: if Phase 8 benchmarks show < 50 ops/sec for American Greeks, queue a v0.2 task to write a `rice`-based binomial backward-induction extension. Don't write it in v0.1.
6. **Dividend handling**: Tenor uses constant dividend yield. v0.2 could support discrete dividends (would require a different tree structure).
7. **Day count convention**: this plan uses Actual/365 Fixed throughout (matching Tenor). Some markets use Actual/360 or 30/360. Document and consider parameterizing in v0.2.

---

## Self-Review Checklist (for the engineer executing this plan)

Before declaring v0.1.0 ready:

- [ ] All RSpec examples pass.
- [ ] Rubocop passes.
- [ ] Regression suite against `tenor_golden.json` passes (or drift report is documented and acceptable).
- [ ] README "Quick example" snippet runs cleanly in `bundle exec irb`.
- [ ] All `docs/*.md` usage examples run cleanly in `bundle exec irb`.
- [ ] README badges all resolve to real targets (CI workflow exists, license link is valid; the RubyGems badge will 404 until publish — that's expected).
- [ ] GitHub Pages source is configured to `main` / `/docs` and the site renders at `https://jayrav13.github.io/ruby-pure-greeks/`.
- [ ] `LICENSE.txt` exists at repo root with MIT text (the README's MIT badge links to it).
- [ ] `release.yml` workflow is in place and the `rubygems` GitHub Environment is wired to RubyGems Trusted Publishing.
- [ ] Benchmarks recorded in `BENCHMARKS.md`.
- [ ] Version bumped to `0.1.0` and `CHANGELOG.md` dated.
- [ ] Release PR is open, CI green; user has explicitly approved the merge that triggers publish.
- [ ] After merge: gem live on RubyGems, GitHub Release `v0.1.0` created with notes.
