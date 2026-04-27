# frozen_string_literal: true

require "pure_greeks/errors"

module PureGreeks
  module ImpliedVolatility
    module BrentSolver
      MAX_ITERATIONS = 100

      module_function

      def find_root(lower:, upper:, tolerance: 1e-8, &f)
        a = lower.to_f
        b = upper.to_f
        fa = f.call(a)
        fb = f.call(b)

        raise IVConvergenceError, "root not bracketed: f(#{a})=#{fa}, f(#{b})=#{fb}" if (fa * fb).positive?

        if fa.abs < fb.abs
          a, b = b, a
          fa, fb = fb, fa
        end

        c = a
        fc = fa
        mflag = true
        d = nil

        MAX_ITERATIONS.times do
          return b if fb.abs < tolerance || (b - a).abs < tolerance

          s =
            if fa != fc && fb != fc
              # Inverse quadratic interpolation
              (a * fb * fc / ((fa - fb) * (fa - fc))) +
                (b * fa * fc / ((fb - fa) * (fb - fc))) +
                (c * fa * fb / ((fc - fa) * (fc - fb)))
            else
              # Secant method
              b - (fb * (b - a) / (fb - fa))
            end

          condition1 = !s.between?([(3 * a + b) / 4, b].min, [(3 * a + b) / 4, b].max)
          condition2 = mflag && (s - b).abs >= (b - c).abs / 2
          condition3 = !mflag && (s - b).abs >= (c - d).abs / 2
          condition4 = mflag && (b - c).abs < tolerance
          condition5 = !mflag && d && (c - d).abs < tolerance

          if condition1 || condition2 || condition3 || condition4 || condition5
            s = (a + b) / 2.0
            mflag = true
          else
            mflag = false
          end

          fs = f.call(s)
          d = c
          c = b
          fc = fb

          if (fa * fs).negative?
            b = s
            fb = fs
          else
            a = s
            fa = fs
          end

          if fa.abs < fb.abs
            a, b = b, a
            fa, fb = fb, fa
          end
        end

        raise IVConvergenceError, "exceeded #{MAX_ITERATIONS} iterations"
      end
    end
  end
end
