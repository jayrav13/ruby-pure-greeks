# frozen_string_literal: true

require "pure_greeks/engines/crr_binomial_american"

RSpec.describe PureGreeks::Engines::CrrBinomialAmerican do
  let(:hull_inputs) do
    {
      type: :call,
      strike: 100.0,
      underlying_price: 100.0,
      time_to_expiry: 1.0,
      implied_volatility: 0.20,
      risk_free_rate: 0.05,
      dividend_yield: 0.0,
      steps: 200
    }
  end

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

  describe ".price" do
    it "American call with no dividends matches European call (Hull ATM)" do
      expect(described_class.price(**hull_inputs)).to be_within(0.02).of(10.4506)
    end

    it "American put with no dividends > European put (early exercise has value)" do
      am_put = described_class.price(**hull_inputs.merge(type: :put))
      expect(am_put).to be_within(0.05).of(6.0395)
      expect(am_put).to be > 5.5735
    end
  end

  describe ".calculate" do
    it "returns Greeks struct for ATM American call (matches BS within tree tolerance)" do
      g = described_class.calculate(**hull_inputs)
      expect(g.price).to be_within(0.02).of(10.4506)
      expect(g.delta).to be_within(0.005).of(0.6368)
      expect(g.gamma).to be_within(0.001).of(0.01876)
      expect(g.model).to eq(:crr_binomial_american)
    end

    it "computes theta close to Black-Scholes equivalent" do
      g = described_class.calculate(**hull_inputs)
      expect(g.theta).to be_within(0.002).of(-0.01757)
    end

    it "computes vega close to Black-Scholes equivalent" do
      g = described_class.calculate(**hull_inputs)
      expect(g.vega).to be_within(0.005).of(0.37524)
    end

    it "computes rho close to Black-Scholes equivalent" do
      g = described_class.calculate(**hull_inputs)
      expect(g.rho).to be_within(0.01).of(0.53232)
    end
  end
end
