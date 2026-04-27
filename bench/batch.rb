# frozen_string_literal: true

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
      implied_volatility: 0.20 + ((i % 10) * 0.05),
      **base_args
    )
  end

  elapsed = Benchmark.realtime do
    options.each(&:greeks)
  end

  puts "#{n} options: #{elapsed.round(3)}s — #{(n / elapsed).round} ops/sec"
end
