# frozen_string_literal: true

require_relative "lib/pure_greeks/version"

Gem::Specification.new do |spec|
  spec.name = "pure_greeks"
  spec.version = PureGreeks::VERSION
  spec.authors = ["Jay Ravaliya"]
  spec.email = ["jayrav13@gmail.com"]

  spec.summary = "Pure-Ruby options Greeks, pricing, and implied volatility for vanilla European and American options."
  spec.description = <<~DESCRIPTION.tr("\n", " ").strip
    Pure-Ruby implementation of Black-Scholes European and CRR Binomial American option pricing
    with delta, gamma, theta, vega, rho, and Brent's-method implied volatility. No Python,
    no QuantLib system dep, no native code.
  DESCRIPTION
  spec.homepage = "https://github.com/jayrav13/ruby-pure-greeks"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "https://jayrav13.github.io/ruby-pure-greeks/"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .github/ .rubocop.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "distribution", "~> 0.8"
  # `distribution` requires `prime` and `bigdecimal`, both of which were
  # extracted from default gems (prime in Ruby 3.1, bigdecimal in 3.4).
  # Declare explicitly so `gem install pure_greeks` works on bare Ruby 3.2+
  # — and importantly, so CI passes on the 3.4 matrix entry.
  spec.add_dependency "bigdecimal", "~> 3.0"
  spec.add_dependency "prime", "~> 0.1"

  spec.add_development_dependency "benchmark-ips", "~> 2.13"
end
