# frozen_string_literal: true

require "pure_greeks/math/normal"

RSpec.describe PureGreeks::Math::Normal do
  describe ".cdf" do
    it "returns 0.5 at zero" do
      expect(described_class.cdf(0.0)).to be_within(1e-10).of(0.5)
    end

    it "returns ~0.8413 at one std dev" do
      expect(described_class.cdf(1.0)).to be_within(1e-4).of(0.8413)
    end

    it "returns ~0.9772 at two std devs" do
      expect(described_class.cdf(2.0)).to be_within(1e-4).of(0.9772)
    end

    it "returns symmetric values around zero" do
      expect(described_class.cdf(-1.5) + described_class.cdf(1.5)).to be_within(1e-10).of(1.0)
    end
  end

  describe ".pdf" do
    it "returns 1/sqrt(2*pi) at zero" do
      expect(described_class.pdf(0.0)).to be_within(1e-10).of(1.0 / ::Math.sqrt(2 * ::Math::PI))
    end

    it "is symmetric" do
      expect(described_class.pdf(-1.7)).to be_within(1e-10).of(described_class.pdf(1.7))
    end
  end
end
