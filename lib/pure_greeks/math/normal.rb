# frozen_string_literal: true

require "distribution"

module PureGreeks
  module Math
    module Normal
      def self.cdf(x)
        Distribution::Normal.cdf(x)
      end

      def self.pdf(x)
        Distribution::Normal.pdf(x)
      end
    end
  end
end
