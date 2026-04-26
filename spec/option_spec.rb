# frozen_string_literal: true

require "pure_greeks"

RSpec.describe PureGreeks::Option do
  let(:valuation_date) { Date.new(2026, 4, 26) }
  let(:expiration) { Date.new(2027, 4, 26) }
  let(:base_args) do
    {
      exercise_style: :american,
      type: :call,
      strike: 100.0,
      expiration: expiration,
      underlying_price: 100.0,
      implied_volatility: 0.20,
      risk_free_rate: 0.05,
      dividend_yield: 0.0,
      valuation_date: valuation_date
    }
  end

  describe "#initialize" do
    it "accepts valid inputs" do
      expect { described_class.new(**base_args) }.not_to raise_error
    end

    it "rejects invalid exercise_style" do
      expect { described_class.new(**base_args.merge(exercise_style: :bermudan)) }
        .to raise_error(PureGreeks::InvalidInputError, /exercise_style/)
    end

    it "rejects invalid type" do
      expect { described_class.new(**base_args.merge(type: :spread)) }
        .to raise_error(PureGreeks::InvalidInputError, /type/)
    end

    it "rejects negative strike" do
      expect { described_class.new(**base_args.merge(strike: -1.0)) }
        .to raise_error(PureGreeks::InvalidInputError)
    end

    it "rejects negative spot" do
      expect { described_class.new(**base_args.merge(underlying_price: 0)) }
        .to raise_error(PureGreeks::InvalidInputError)
    end

    it "rejects expired contract" do
      expect { described_class.new(**base_args.merge(expiration: valuation_date - 1)) }
        .to raise_error(PureGreeks::ExpiredContractError)
    end
  end

  describe "Greeks accessors" do
    subject(:option) { described_class.new(**base_args) }

    it "exposes price, delta, gamma, theta, vega, rho" do
      expect(option.price).to be > 0
      expect(option.delta).to be_within(0.005).of(0.6368)
      expect(option.gamma).to be_within(0.001).of(0.01876)
      expect(option.theta).to be < 0
      expect(option.vega).to be > 0
    end

    it "exposes greeks struct" do
      expect(option.greeks).to be_a(PureGreeks::Greeks)
    end

    it "caches the greeks computation" do
      expect(PureGreeks::Engines::FallbackChain).to receive(:calculate).once.and_call_original
      option.delta
      option.gamma
      option.greeks
    end

    it "exposes calculation_model" do
      expect(option.calculation_model).to eq(:crr_binomial_american)
    end
  end
end
