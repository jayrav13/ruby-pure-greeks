# frozen_string_literal: true

require "pure_greeks/engines/black_scholes_european"
require "pure_greeks/engines/crr_binomial_american"
require "pure_greeks/engines/intrinsic"

module PureGreeks
  module Engines
    module FallbackChain
      module_function

      def calculate(exercise_style:, type:, strike:, underlying_price:, time_to_expiry:,
                    implied_volatility:, risk_free_rate:, dividend_yield:)
        return Intrinsic.calculate(type: type, strike: strike, underlying_price: underlying_price) if implied_volatility <= 0.0

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
            # fall through to BS European
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
