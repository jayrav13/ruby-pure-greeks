# frozen_string_literal: true

module PureGreeks
  Greeks = Data.define(:delta, :gamma, :theta, :vega, :rho, :price, :model)
end
