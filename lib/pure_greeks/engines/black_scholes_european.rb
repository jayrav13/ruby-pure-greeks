# frozen_string_literal: true

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
