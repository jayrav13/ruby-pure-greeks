# frozen_string_literal: true

require "pure_greeks/engines/black_scholes_european"

RSpec.describe PureGreeks::Engines::BlackScholesEuropean do
  let(:hull_inputs) do
    {
      type: :call,
      strike: 100.0,
      underlying_price: 100.0,
      time_to_expiry: 1.0,
      implied_volatility: 0.20,
      risk_free_rate: 0.05,
      dividend_yield: 0.0
    }
  end

  describe ".price" do
    it "matches Hull reference for at-the-money call" do
      expect(described_class.price(**hull_inputs)).to be_within(1e-3).of(10.4506)
    end
  end
end
