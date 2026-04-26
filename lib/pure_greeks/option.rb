# frozen_string_literal: true

require "date"
require "pure_greeks/errors"
require "pure_greeks/engines/fallback_chain"
require "pure_greeks/engines/black_scholes_european"
require "pure_greeks/implied_volatility/brent_solver"

module PureGreeks
  class Option
    VALID_EXERCISE_STYLES = %i[american european].freeze
    VALID_TYPES = %i[call put].freeze
    DAYS_PER_YEAR = 365.0

    attr_reader :exercise_style, :type, :strike, :expiration, :underlying_price,
                :risk_free_rate, :dividend_yield, :valuation_date

    def initialize(exercise_style:, type:, strike:, expiration:, underlying_price:,
                   risk_free_rate:, dividend_yield:, valuation_date:,
                   implied_volatility: nil, market_price: nil)
      validate!(exercise_style, type, strike, underlying_price, expiration, valuation_date)

      @exercise_style = exercise_style
      @type = type
      @strike = strike.to_f
      @expiration = expiration
      @underlying_price = underlying_price.to_f
      @implied_volatility = implied_volatility&.to_f
      @market_price = market_price&.to_f
      @risk_free_rate = risk_free_rate.to_f
      @dividend_yield = dividend_yield.to_f
      @valuation_date = valuation_date
    end

    def time_to_expiry
      (@expiration - @valuation_date).to_f / DAYS_PER_YEAR
    end

    def greeks
      @greeks ||= compute_greeks
    end

    def price
      greeks.price
    end

    def delta
      greeks.delta
    end

    def gamma
      greeks.gamma
    end

    def theta
      greeks.theta
    end

    def vega
      greeks.vega
    end

    def rho
      greeks.rho
    end

    def calculation_model
      greeks.model
    end

    def implied_volatility
      return @implied_volatility if @implied_volatility
      raise InvalidInputError, "market_price required to solve for implied_volatility" unless @market_price

      @implied_volatility = ImpliedVolatility::BrentSolver.find_root(lower: 1e-6, upper: 5.0, tolerance: 1e-6) do |sigma|
        Engines::BlackScholesEuropean.price(
          type: @type,
          strike: @strike,
          underlying_price: @underlying_price,
          time_to_expiry: time_to_expiry,
          implied_volatility: sigma,
          risk_free_rate: @risk_free_rate,
          dividend_yield: @dividend_yield
        ) - @market_price
      end
    end

    private

    def compute_greeks
      Engines::FallbackChain.calculate(
        exercise_style: @exercise_style,
        type: @type,
        strike: @strike,
        underlying_price: @underlying_price,
        time_to_expiry: time_to_expiry,
        implied_volatility: @implied_volatility,
        risk_free_rate: @risk_free_rate,
        dividend_yield: @dividend_yield
      )
    end

    def validate!(exercise_style, type, strike, spot, expiration, valuation_date)
      unless VALID_EXERCISE_STYLES.include?(exercise_style)
        raise InvalidInputError, "exercise_style must be one of #{VALID_EXERCISE_STYLES}"
      end
      raise InvalidInputError, "type must be one of #{VALID_TYPES}" unless VALID_TYPES.include?(type)
      raise InvalidInputError, "strike must be positive" unless strike.is_a?(Numeric) && strike.positive?
      raise InvalidInputError, "underlying_price must be positive" unless spot.is_a?(Numeric) && spot.positive?
      raise ExpiredContractError, "contract expired on #{expiration}" if expiration <= valuation_date
    end
  end
end
