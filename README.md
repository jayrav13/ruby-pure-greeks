# pure_greeks

[![Gem Version](https://badge.fury.io/rb/pure_greeks.svg)](https://rubygems.org/gems/pure_greeks)
[![CI](https://github.com/jayrav13/ruby-pure-greeks/actions/workflows/ci.yml/badge.svg)](https://github.com/jayrav13/ruby-pure-greeks/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Pure-Ruby options Greeks (delta, gamma, theta, vega, rho), pricing, and implied volatility for vanilla European and American options. No Python, no QuantLib system dep, no native code.

**Documentation, examples, and engine internals: https://jayravaliya.com/ruby-pure-greeks/**

## Author's note

Hi folks! I've been working on some options-related projects recently and came across the need to calculate options greeks in Ruby. The solution was to invoke a Python script from a Rails app to generate these numbers and then ingest. That was fine, but I saw that there was a vacuum in this type of library in the Ruby world, so I decided to pair with Claude and make it.

Check out the great details available on the Pages site about the different strategies available. Contributions welcome!

---

## Installation

Add to your Gemfile:

```ruby
gem "pure_greeks"
```

Then `bundle install`. Or install directly:

```bash
gem install pure_greeks
```

Requires Ruby 3.2 or newer. No system dependencies.

## Quick example

```ruby
require "pure_greeks"

option = PureGreeks::Option.new(
  exercise_style: :american, type: :call,
  strike: 150.0, expiration: Date.new(2026, 6, 19),
  underlying_price: 148.5, implied_volatility: 0.35,
  risk_free_rate: 0.05, dividend_yield: 0.0,
  valuation_date: Date.today
)

option.price   # => 4.27
option.delta   # => 0.42
```

For the full API, the implied-volatility solver, how the three engines fall back to one another, validation methodology, and limitations, see the [documentation site](https://jayravaliya.com/ruby-pure-greeks/).

## Development

Clone and bootstrap:

```bash
git clone https://github.com/jayrav13/ruby-pure-greeks.git
cd ruby-pure-greeks
bin/setup
```

Run the test suite:

```bash
bundle exec rspec
```

Run the linter:

```bash
bundle exec rubocop
```

Open a console with the gem loaded:

```bash
bin/console
```

To install this gem onto your local machine for trial use:

```bash
bundle exec rake install
```

## Releasing

Releases are tag-driven through CI — no manual `gem push` needed.

1. On a feature branch, bump `lib/pure_greeks/version.rb` to the new version.
2. Add a section to `CHANGELOG.md` for the new version (Keep-a-Changelog format).
3. Open a PR; CI must be green.
4. Merge to `main`. The release workflow (`.github/workflows/release.yml`) detects the version bump, runs the test suite, builds the gem, publishes to RubyGems via [Trusted Publishing](https://guides.rubygems.org/trusted-publishing/) (no API key), creates a `vX.Y.Z` git tag, and opens a GitHub Release with auto-generated notes from the merged PRs.

The RubyGems version badge above refreshes automatically once the new version indexes on rubygems.org (usually within a minute).

## Contributing

Bug reports and pull requests are welcome at https://github.com/jayrav13/ruby-pure-greeks. Please run `bundle exec rspec` and `bundle exec rubocop` locally before opening a PR. CI runs both on Ruby 3.2, 3.3, and 3.4.

## License

MIT. See `LICENSE.txt`.
