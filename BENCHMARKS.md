# Benchmarks — pure_greeks v0.1.0

Measured on Apple Silicon (arm64-darwin22), Ruby 3.2.0, MRI. Hardware-dependent — your numbers will differ. Re-run on your machine before relying on them.

## Single-option microbenchmark

`bundle exec ruby bench/single_option.rb`

```
American CRR (200 steps)        83.4 i/s   (12.0 ms per call)
European Black-Scholes      147,500   i/s   ( 6.8 µs per call)
```

The American number is dominated by the CRR backward-induction tree (200 steps × up to 200 nodes per step = ~40k node operations per call, plus two more full tree solves for vega and rho via finite difference). The European number is essentially the cost of the Black-Scholes closed form plus three extra `Distribution::Normal.cdf` calls.

## Batch benchmark

`bundle exec ruby bench/batch.rb` (American, mixed calls/puts, IVs in [0.20, 0.65]):

| batch size | wall time | throughput |
|-----------:|----------:|-----------:|
|        100 |     1.2 s |  84 ops/s  |
|      1,000 |    11.9 s |  84 ops/s  |
|     10,000 |   122.1 s |  82 ops/s  |

Throughput is flat across batch sizes — no GC pressure or hot-path memoization wins, just the per-tree cost compounding linearly. This is the expected shape for pure-Ruby CRR.

## v0.1 ship decision

Tenor's QuantLib pipeline (`GreeksCalculationBatchJob`) processes ~5,000–15,000 options per batch in ~30–60 s, i.e. ~250 ops/s. Our 83 ops/s on the same workload is **~33% of QuantLib's throughput** — acceptable for interactive use and most batch jobs, but slow for large nightly Greeks computations.

The plan's pure-Ruby ship threshold was 50 ops/s; we're comfortably above that. Ship pure Ruby for v0.1; queue performance work for v0.2.

## Performance backlog (v0.2 candidates)

Roughly ordered by expected impact:

1. **Reuse the baseline CRR tree across the σ and r bumps.** Today, vega and rho rebuild the entire tree with a perturbed parameter (3× cost). With careful state separation we can reuse the leaf payoffs and replay only the affected step. Expected: ~3× speedup on American Greeks. Risk: easy to introduce subtle numerical drift if the bumped tree's `dt`, `u`, `d`, `p`, `disc` aren't fully recomputed.
2. **Drop default `steps` from 200 to 100.** O(N²) tree work, so this is a 4× speedup. Risk: extreme-IV or near-expiry rows lose accuracy — verify against the regression suite before adopting.
3. **C extension for backward induction** (`rice` or a direct Ruby C extension). Estimated 10–50× speedup on the inner loop. Risk: native code re-introduces the install-friction problem this gem exists to solve. Worth doing only if v0.1 throughput becomes a real bottleneck.

## How to re-run

```bash
bundle install
bundle exec ruby bench/single_option.rb     # microbenchmark with benchmark/ips
bundle exec ruby bench/batch.rb              # batch sweep at 100 / 1k / 10k
```

`benchmark-ips` is in the gemspec as a `development_dependency`, so `bundle install` pulls it in for the gem checkout but it isn't required for end users.
