# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

# Default `rake spec` and CI run only unit tests. The regression suite
# (spec/regression/) compares against Tenor's QuantLib golden dataset and is
# slow + has known IV-pipeline drift; run it explicitly with `rake regression`.
RSpec::Core::RakeTask.new(:spec) do |t|
  t.exclude_pattern = "spec/regression/**/*_spec.rb"
end

RSpec::Core::RakeTask.new(:regression) do |t|
  t.pattern = "spec/regression/**/*_spec.rb"
end

require "rubocop/rake_task"

RuboCop::RakeTask.new

task default: %i[spec rubocop]
