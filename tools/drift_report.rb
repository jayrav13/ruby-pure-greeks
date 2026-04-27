#!/usr/bin/env ruby
# frozen_string_literal: true

# One-shot diagnostic: compute drift between PureGreeks and Tenor's
# QuantLib output across the entire golden fixture. Used during Phase 7
# to characterize regression drift before deciding on test tolerances.

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "json"
require "date"
require "pure_greeks"

fixture = JSON.parse(File.read(File.expand_path("../spec/regression/fixtures/tenor_golden.json", __dir__)))

EXERCISE_STYLE = {
  "quantlib_american" => :american,
  "quantlib_european" => :european
}.freeze

GREEKS = %i[price delta gamma theta vega rho].freeze

drifts = Hash.new { |h, k| h[k] = [] }
errors = []

fixture["rows"].each do |row|
  option = PureGreeks::Option.new(
    exercise_style: EXERCISE_STYLE.fetch(row["calculation_model"]),
    type: row["option_type"].to_sym,
    strike: row["strike"],
    expiration: Date.parse(row["expiration"]),
    underlying_price: row["underlying_price"],
    implied_volatility: row["implied_volatility"],
    risk_free_rate: row["risk_free_rate"],
    dividend_yield: row["dividend_yield"],
    valuation_date: Date.parse(row["snapshot_date"])
  )

  GREEKS.each do |g|
    mine = option.public_send(g)
    expected = g == :price ? row["calculated_price"] : row[g.to_s]
    next if expected.nil?

    drifts[g] << {
      abs: (mine - expected).abs,
      mine: mine, expected: expected,
      iv: row["implied_volatility"],
      ttm: (Date.parse(row["expiration"]) - Date.parse(row["snapshot_date"])).to_f / 365.0,
      moneyness: row["underlying_price"] / row["strike"],
      type: row["option_type"], style: row["calculation_model"],
      snapshot: row["snapshot_id"]
    }
  end
rescue StandardError => e
  errors << { row: row["snapshot_id"], error: e.message }
end

def stats(arr)
  vals = arr.map { |d| d[:abs] }
  sorted = vals.sort
  {
    n: vals.size,
    mean: vals.sum / vals.size.to_f,
    p50: sorted[sorted.size / 2],
    p95: sorted[(sorted.size * 0.95).to_i],
    p99: sorted[(sorted.size * 0.99).to_i],
    max: sorted.last
  }
end

puts "=== Drift summary (absolute |mine - expected|) ==="
puts format("%-7s %5s %12s %12s %12s %12s %12s", "greek", "n", "mean", "p50", "p95", "p99", "max")
GREEKS.each do |g|
  s = stats(drifts[g])
  puts format("%-7s %5d %12.6g %12.6g %12.6g %12.6g %12.6g", g, s[:n], s[:mean], s[:p50], s[:p95], s[:p99], s[:max])
end

puts "\n=== Pass-rate at proposed tolerances (Greek absolute, price relative) ==="
proposed = { price_rel: 0.05, price_abs: 0.10, delta: 0.01, gamma: 0.005,
             theta: 0.005, vega: 0.05, rho: 0.15 }
pass_counts = Hash.new(0)
total = drifts[:price].size
total.times do |i|
  failures = []
  failures << :price if drifts[:price][i][:abs] > [proposed[:price_abs], proposed[:price_rel] * drifts[:price][i][:expected].abs].max
  failures << :delta if drifts[:delta][i][:abs] > proposed[:delta]
  failures << :gamma if drifts[:gamma][i][:abs] > proposed[:gamma]
  failures << :theta if drifts[:theta][i][:abs] > proposed[:theta]
  failures << :vega if drifts[:vega][i][:abs] > proposed[:vega]
  failures << :rho if drifts[:rho][i][:abs] > proposed[:rho]
  pass_counts[:all] += 1 if failures.empty?
  failures.each { |g| pass_counts[g] += 1 }
end
puts "  proposed tolerances: #{proposed.inspect}"
puts "  rows passing all: #{total - pass_counts[:all]} fail / #{total} total = #{((total - pass_counts[:all]) * 100.0 / total).round(1)}%"
%i[price delta gamma theta vega rho].each do |g|
  puts "    #{g}: #{pass_counts[g]} fail (#{(pass_counts[g] * 100.0 / total).round(1)}%)"
end

puts "\n=== Top-5 worst price drifts ==="
drifts[:price].sort_by { |d| -d[:abs] }.first(5).each do |d|
  puts format("  %s | %s/%s | iv=%.3f ttm=%.2fy moneyness=%.2f | mine=%.4f expected=%.4f drift=%.4f",
              d[:snapshot][0, 8], d[:type], d[:style], d[:iv], d[:ttm], d[:moneyness],
              d[:mine], d[:expected], d[:abs])
end

if errors.any?
  puts "\n=== Errors during compute (#{errors.size}) ==="
  errors.first(5).each { |e| puts "  #{e[:row][0, 8]}: #{e[:error]}" }
end
