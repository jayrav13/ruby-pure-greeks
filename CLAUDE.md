# CLAUDE.md — pure_greeks

## The rule

Any change that affects public behavior, performance, validation, or
metadata **must** update every relevant doc surface **in the same PR**.
Docs that go stale silently are worse than docs that are missing —
readers learn not to trust them.

`PLAN.md` is frozen historical context from the v0.1 build-out and is
**not** maintained. Don't edit it on new changes.

## Which doc owns which kind of change

| Change | Update |
|---|---|
| New or changed public API (constructor args, accessors, errors raised) | `docs/usage.md` (constructor table + relevant section), `CHANGELOG.md` |
| New engine, fallback rule, or numerical method change | `docs/engines.md`, plus `docs/usage.md` if it surfaces in the public API |
| Performance change (faster, slower, new optimization, default-step change) | `BENCHMARKS.md` (re-run benches and update the tables + v0.2 backlog), `CHANGELOG.md` if user-visible |
| New known limitation discovered (e.g. unsupported regime) | `docs/limitations.md` |
| Validation methodology / regression tolerance change | `REGRESSION_REPORT.md` and `docs/validation.md` (Hull tolerances live in the unit specs themselves; if those change, mention it in the report) |
| RubyGems metadata change (runtime deps, license, URLs, summary) | `pure_greeks.gemspec`, the `## Releasing` section if the flow changes, and `CHANGELOG.md` |
| Release workflow or CI workflow change | The relevant `.github/workflows/*.yml`, plus `README.md` "Releasing" section if it changes the user-facing flow |

If a change clearly touches multiple categories, all of them apply. If
it touches none of them (refactors, internal cleanup with no behavior
change), no docs change is required — but write that in the PR
description so it's intentional, not an oversight.

## Docs site URL

The Pages docs render at https://jayravaliya.com/ruby-pure-greeks/ —
not at the github.io URL. The reason that domain is shared and how
routing works there is documented at:

https://github.com/jayrav13/jayrav13.github.io/blob/main/CLAUDE.md

Don't duplicate the routing rules here; just remember that when you
visit the docs to verify a change, that's the URL.

## Default test command

`bundle exec rspec` runs the unit suite and excludes the regression
suite. Use `bundle exec rake regression` (or `RUN_REGRESSION=1 rspec`)
when you specifically want to run the Tenor golden-dataset comparison.
