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

    it "matches Hull reference for at-the-money put" do
      expect(described_class.price(**hull_inputs.merge(type: :put))).to be_within(1e-3).of(5.5735)
    end

    it "satisfies put-call parity" do
      call = described_class.price(**hull_inputs)
      put = described_class.price(**hull_inputs.merge(type: :put))
      s = 100.0
      k = 100.0
      r = 0.05
      q = 0.0
      t = 1.0
      parity = call - put - (s * ::Math.exp(-q * t) - k * ::Math.exp(-r * t))
      expect(parity).to be_within(1e-10).of(0.0)
    end
  end

  describe ".calculate" do
    it "returns Greeks struct matching Hull reference for ATM call" do
      g = described_class.calculate(**hull_inputs)
      expect(g.price).to be_within(1e-3).of(10.4506)
      expect(g.delta).to be_within(1e-4).of(0.6368)
      expect(g.gamma).to be_within(1e-5).of(0.01876)
      expect(g.theta).to be_within(1e-4).of(-0.01757)
      expect(g.vega).to be_within(1e-4).of(0.37524)
      expect(g.rho).to be_within(1e-3).of(0.53232)
      expect(g.model).to eq(:black_scholes_european)
    end

    it "returns negative delta for put" do
      g = described_class.calculate(**hull_inputs.merge(type: :put))
      expect(g.delta).to be_within(1e-4).of(-0.3632)
    end
  end
end
