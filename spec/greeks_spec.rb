# frozen_string_literal: true

require "pure_greeks/greeks"

RSpec.describe PureGreeks::Greeks do
  let(:greeks) do
    described_class.new(
      delta: 0.5,
      gamma: 0.02,
      theta: -0.01,
      vega: 0.15,
      rho: 0.08,
      price: 4.25,
      model: :black_scholes_european
    )
  end

  it "exposes all six numeric fields" do
    expect(greeks.delta).to eq(0.5)
    expect(greeks.gamma).to eq(0.02)
    expect(greeks.theta).to eq(-0.01)
    expect(greeks.vega).to eq(0.15)
    expect(greeks.rho).to eq(0.08)
    expect(greeks.price).to eq(4.25)
  end

  it "exposes the model symbol" do
    expect(greeks.model).to eq(:black_scholes_european)
  end

  it "is immutable" do
    expect { greeks.delta = 0.7 }.to raise_error(NoMethodError)
  end
end
