# frozen_string_literal: true

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
