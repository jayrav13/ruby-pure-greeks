# frozen_string_literal: true

module PureGreeks
  class Error < StandardError; end
  class InvalidInputError < Error; end
  class ExpiredContractError < InvalidInputError; end
  class CalculationError < Error; end
  class IVConvergenceError < CalculationError; end
end
