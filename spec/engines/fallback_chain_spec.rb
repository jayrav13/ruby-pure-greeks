# frozen_string_literal: true

require "pure_greeks/engines/fallback_chain"

RSpec.describe PureGreeks::Engines::FallbackChain do
  let(:base_inputs) do
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

  describe ".calculate" do
    it "uses CRR for American exercise style" do
      g = described_class.calculate(exercise_style: :american, **base_inputs)
      expect(g.model).to eq(:crr_binomial_american)
    end

    it "uses BS European for European exercise style" do
      g = described_class.calculate(exercise_style: :european, **base_inputs)
      expect(g.model).to eq(:black_scholes_european)
    end

    it "falls back to intrinsic when IV <= 0" do
      g = described_class.calculate(exercise_style: :american, **base_inputs.merge(implied_volatility: 0.0))
      expect(g.model).to eq(:intrinsic)
    end

    it "falls back to BS European when CRR raises" do
      allow(PureGreeks::Engines::CrrBinomialAmerican).to receive(:calculate).and_raise("simulated CRR failure")
      g = described_class.calculate(exercise_style: :american, **base_inputs)
      expect(g.model).to eq(:black_scholes_european)
    end

    it "falls back to intrinsic when both CRR and BS raise" do
      allow(PureGreeks::Engines::CrrBinomialAmerican).to receive(:calculate).and_raise("simulated CRR failure")
      allow(PureGreeks::Engines::BlackScholesEuropean).to receive(:calculate).and_raise("simulated BS failure")
      g = described_class.calculate(exercise_style: :american, **base_inputs)
      expect(g.model).to eq(:intrinsic)
    end
  end
end
