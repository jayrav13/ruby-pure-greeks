# frozen_string_literal: true

require "pure_greeks/implied_volatility/brent_solver"

RSpec.describe PureGreeks::ImpliedVolatility::BrentSolver do
  describe ".find_root" do
    it "finds root of x^2 - 4 in [1, 3] (= 2.0)" do
      root = described_class.find_root(lower: 1.0, upper: 3.0, tolerance: 1e-9) { |x| (x**2) - 4.0 }
      expect(root).to be_within(1e-9).of(2.0)
    end

    it "finds root of cos(x) - x near 0.7390851" do
      root = described_class.find_root(lower: 0.0, upper: 1.0, tolerance: 1e-9) { |x| ::Math.cos(x) - x }
      expect(root).to be_within(1e-9).of(0.7390851332151607)
    end

    it "raises if root is not bracketed" do
      expect do
        described_class.find_root(lower: 5.0, upper: 10.0, tolerance: 1e-6) { |x| (x**2) - 4.0 }
      end.to raise_error(PureGreeks::IVConvergenceError, /not bracketed/)
    end
  end
end
