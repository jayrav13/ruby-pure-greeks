# frozen_string_literal: true

require "pure_greeks/engines/intrinsic"

RSpec.describe PureGreeks::Engines::Intrinsic do
  describe ".calculate" do
    it "in-the-money call: intrinsic = spot - strike, delta = 1" do
      g = described_class.calculate(type: :call, strike: 100.0, underlying_price: 110.0)
      expect(g.price).to eq(10.0)
      expect(g.delta).to eq(1.0)
      expect(g.gamma).to eq(0.0)
      expect(g.model).to eq(:intrinsic)
    end

    it "out-of-the-money call: intrinsic = 0, delta = 0" do
      g = described_class.calculate(type: :call, strike: 100.0, underlying_price: 90.0)
      expect(g.price).to eq(0.0)
      expect(g.delta).to eq(0.0)
    end

    it "in-the-money put: intrinsic = strike - spot, delta = -1" do
      g = described_class.calculate(type: :put, strike: 100.0, underlying_price: 90.0)
      expect(g.price).to eq(10.0)
      expect(g.delta).to eq(-1.0)
    end

    it "out-of-the-money put: intrinsic = 0, delta = 0" do
      g = described_class.calculate(type: :put, strike: 100.0, underlying_price: 110.0)
      expect(g.price).to eq(0.0)
      expect(g.delta).to eq(0.0)
    end
  end
end
