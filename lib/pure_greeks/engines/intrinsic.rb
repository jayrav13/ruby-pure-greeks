# frozen_string_literal: true

require "pure_greeks/greeks"

module PureGreeks
  module Engines
    module Intrinsic
      module_function

      def calculate(type:, strike:, underlying_price:)
        if type == :call
          price = [0.0, underlying_price - strike].max
          delta = underlying_price > strike ? 1.0 : 0.0
        else
          price = [0.0, strike - underlying_price].max
          delta = underlying_price < strike ? -1.0 : 0.0
        end

        Greeks.new(
          delta: delta,
          gamma: 0.0,
          theta: 0.0,
          vega: 0.0,
          rho: 0.0,
          price: price,
          model: :intrinsic
        )
      end
    end
  end
end
