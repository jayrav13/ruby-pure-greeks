# frozen_string_literal: true

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

      def price(type:, strike:, underlying_price:, time_to_expiry:, implied_volatility:,
                risk_free_rate:, dividend_yield:, steps: DEFAULT_STEPS)
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
    end
  end
end
