# frozen_string_literal: true

require "pure_greeks"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Regression suite is slow and has documented IV-pipeline drift (see
  # REGRESSION_REPORT.md). Run it explicitly with `rake regression` or
  # `RUN_REGRESSION=1 rspec`.
  config.filter_run_excluding(:regression) unless ENV["RUN_REGRESSION"]
end
