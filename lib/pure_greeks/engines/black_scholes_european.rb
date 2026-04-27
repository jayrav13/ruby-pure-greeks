# frozen_string_literal: true

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
        delta = if type == :call
                  ::Math.exp(-dividend_yield * time_to_expiry) * nd1
                else
                  -::Math.exp(-dividend_yield * time_to_expiry) * n_neg_d1
                end
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
