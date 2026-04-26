# frozen_string_literal: true

require "pure_greeks/engines/crr_binomial_american"

RSpec.describe PureGreeks::Engines::CrrBinomialAmerican do
  describe ".tree_parameters" do
    it "computes u, d, p, disc for given inputs" do
      params = described_class.tree_parameters(
        time_to_expiry: 1.0,
        steps: 200,
        implied_volatility: 0.20,
        risk_free_rate: 0.05,
        dividend_yield: 0.0
      )
      dt = 1.0 / 200.0
      expect(params[:dt]).to be_within(1e-12).of(dt)
      expect(params[:u]).to be_within(1e-10).of(::Math.exp(0.20 * ::Math.sqrt(dt)))
      expect(params[:d]).to be_within(1e-10).of(1.0 / params[:u])
      expect(params[:p]).to be > 0.0
      expect(params[:p]).to be < 1.0
      expect(params[:disc]).to be_within(1e-10).of(::Math.exp(-0.05 * dt))
    end
  end
end
