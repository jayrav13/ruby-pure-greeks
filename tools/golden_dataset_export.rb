#!/usr/bin/env ruby
# frozen_string_literal: true

# Manual one-shot tool to export a golden dataset from Tenor's prod DB.
#
# This script is NOT run as part of the gem or CI. It documents the
# query and the JSON shape so the fixture can be regenerated reproducibly.
#
# Prerequisites:
#   - psql in $PATH
#   - Tenor's connection string available at ~/Code/tenor/.mcp.json
#   - jq in $PATH (used to extract the connection string)
#
# Output: spec/regression/fixtures/tenor_golden.json
#
# READ-ONLY. The query below must remain a single SELECT; do not modify
# it to write to the source database.

require "json"
require "open3"
require "time"

GOLDEN_DATASET_QUERY = <<~SQL
  SELECT
    g.snapshot_id::text                AS snapshot_id,
    s.option_type                      AS option_type,
    s.strike::float8                   AS strike,
    s.expiration::text                 AS expiration,
    s.snapshot_date::text              AS snapshot_date,
    s.underlying_price::float8         AS underlying_price,
    s.implied_volatility::float8       AS implied_volatility,
    COALESCE(g.dividend_yield, 0)::float8 AS dividend_yield,
    g.risk_free_rate::float8           AS risk_free_rate,
    g.delta::float8                    AS delta,
    g.gamma::float8                    AS gamma,
    g.theta::float8                    AS theta,
    g.vega::float8                     AS vega,
    g.rho::float8                      AS rho,
    g.calculated_price::float8         AS calculated_price,
    g.calculation_model                AS calculation_model
  FROM options.greeks g
  JOIN options.snapshots s ON s.id = g.snapshot_id
  WHERE g.calculation_model IN ('quantlib_american', 'quantlib_european')
    AND s.option_type IN ('calls', 'puts')
    AND s.strike IS NOT NULL
    AND s.underlying_price IS NOT NULL
    AND s.implied_volatility IS NOT NULL
    AND s.implied_volatility > 0
    AND s.expiration IS NOT NULL
    AND s.expiration > s.snapshot_date
    AND g.risk_free_rate IS NOT NULL
    AND g.delta IS NOT NULL
    AND g.gamma IS NOT NULL
    AND g.theta IS NOT NULL
    AND g.vega IS NOT NULL
    AND g.rho IS NOT NULL
    AND g.calculated_price IS NOT NULL
  ORDER BY RANDOM()
  LIMIT 500;
SQL

OPTION_TYPE_MAP = { "calls" => "call", "puts" => "put" }.freeze
NUMERIC_FIELDS = %w[
  strike underlying_price implied_volatility dividend_yield risk_free_rate
  delta gamma theta vega rho calculated_price
].freeze

def main
  pg_url = `jq -r '.mcpServers."postgres-prod".args[2]' ~/Code/tenor/.mcp.json`.strip
  raise "could not read postgres-prod connection string" if pg_url.empty?

  stdout, stderr, status = Open3.capture3(
    "psql", pg_url, "--csv", "--pset=footer=off",
    "-c", GOLDEN_DATASET_QUERY
  )
  raise "psql failed: #{stderr}" unless status.success?

  rows = parse_csv(stdout)
  rows = normalize_rows(rows)

  output = {
    "_meta" => {
      "exported_at" => Time.now.utc.iso8601,
      "source" => "Tenor prod DB (options.greeks JOIN options.snapshots)",
      "rate_source" => "options.greeks.risk_free_rate per row " \
                       "(Tenor backfills options.risk_free_rates from FRED)",
      "calculation_models" => %w[quantlib_american quantlib_european],
      "sampling" => "ORDER BY RANDOM() LIMIT 500",
      "row_count" => rows.size,
      "tool" => "tools/golden_dataset_export.rb"
    },
    "rows" => rows
  }

  fixture_path = File.expand_path("../spec/regression/fixtures/tenor_golden.json", __dir__)
  File.write(fixture_path, JSON.pretty_generate(output))
  puts "Wrote #{rows.size} rows to #{fixture_path}"
end

def parse_csv(blob)
  require "csv"
  table = CSV.parse(blob, headers: true)
  table.map(&:to_h)
end

def normalize_rows(rows)
  rows.map do |row|
    NUMERIC_FIELDS.each { |k| row[k] = row[k].to_f }
    row["option_type"] = OPTION_TYPE_MAP.fetch(row["option_type"]) do |t|
      raise "unexpected option_type=#{t.inspect} on row=#{row.inspect}"
    end
    row
  end
end

main if $PROGRAM_NAME == __FILE__
