# frozen_string_literal: true

require "pure_greeks/greeks"

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

      def calculate(type:, strike:, underlying_price:, time_to_expiry:, implied_volatility:,
                    risk_free_rate:, dividend_yield:, steps: DEFAULT_STEPS)
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

        delta = (v_step1[0] - v_step1[1]) / (underlying_price * u - underlying_price * d)

        s_uu = underlying_price * u * u
        s_ud = underlying_price * u * d
        s_dd = underlying_price * d * d
        delta_upper = (v_step2[0] - v_step2[1]) / (s_uu - s_ud)
        delta_lower = (v_step2[1] - v_step2[2]) / (s_ud - s_dd)
        gamma = (delta_upper - delta_lower) / (0.5 * (s_uu - s_dd))

        theta = (v_step2[1] - price) / (2.0 * params[:dt]) / 365.0

        bumped_vol_params = tree_parameters(
          time_to_expiry: time_to_expiry,
          steps: steps,
          implied_volatility: implied_volatility + 0.01,
          risk_free_rate: risk_free_rate,
          dividend_yield: dividend_yield
        )
        price_vol_up = backward_induct_with_intermediates(type, strike, underlying_price, steps, bumped_vol_params)[:price]
        vega = (price_vol_up - price) / (0.01 * 100.0)

        bumped_rate_params = tree_parameters(
          time_to_expiry: time_to_expiry,
          steps: steps,
          implied_volatility: implied_volatility,
          risk_free_rate: risk_free_rate + 0.01,
          dividend_yield: dividend_yield
        )
        price_rate_up = backward_induct_with_intermediates(type, strike, underlying_price, steps, bumped_rate_params)[:price]
        rho = (price_rate_up - price) / (0.01 * 100.0)

        Greeks.new(
          delta: delta,
          gamma: gamma,
          theta: theta,
          vega: vega,
          rho: rho,
          price: price,
          model: :crr_binomial_american
        )
      end

      def price(**args)
        calculate(**args).price
      end

      def backward_induct(type, strike, spot, steps, params)
        backward_induct_with_intermediates(type, strike, spot, steps, params)[:price]
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
    end
  end
end
