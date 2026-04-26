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
    end
  end
end
