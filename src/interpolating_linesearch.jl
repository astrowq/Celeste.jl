# Copied from Optim.jl
using Optim

function interpolating_linesearch!{T}(d::Union(DifferentiableFunction,
                                               TwiceDifferentiableFunction),
                                      x::Vector,
                                      p::Vector,
                                      x_new::Vector,
                                      gr_new::Vector,
                                      lsr::Optim.LineSearchResults{T},
                                      c::Real,
                                      mayterminate::Bool;
                                      c1::Real = 1e-4,
                                      c2::Real = 0.9,
                                      rho::Real = 2.0,
                                      verbose::Bool = false)

    # Parameter space
    n = length(x)

    # Count function calls
    f_calls, g_calls = 0, 0

    # Step-sizes
    a_0 = 0.0
    a_iminus1 = a_0
    a_i = 1.0
    a_max = 65536.0

    # phi(alpha) = f(x + alpha * p)
    phi_0 = d.f(x)
    f_calls += 1
    phi_a_iminus1 = phi_0
    phi_a_i = NaN

    # phi'(alpha) = dot(g(x + alpha * p), p)
    d.g!(x, gr_new)
    g_calls += 1
    phiprime_0 = dot(gr_new, p)
    phiprime_a_i = NaN
    phiprime_0 < 0 || error("p is not a descent direction")
    @assert !isnan(phiprime_0)
    @assert !isnan(phi_0)

    # Iteration counter
    i = 1

    while a_i < a_max
        # Update x_new
        for index in 1:n
            x_new[index] = x[index] + a_i * p[index]
        end
        verbose && println("----------\n$a_i\n$x_new")

        # Evaluate phi(a_i)
        phi_a_i = d.f(x_new)
        f_calls += 1

        # Test Wolfe conditions
        if (phi_a_i > phi_0 + c1 * a_i * phiprime_0) ||
             (phi_a_i >= phi_a_iminus1 && i > 1) ||
             isnan(phi_a_i)
            verbose && println("Zoom for wolfe condition")
            a_star, f_up, g_up = zoom(a_iminus1, a_i,
                                      phiprime_0, phi_0,
                                      d.f, d.g!, x, p, x_new, gr_new, verbose=verbose)
            return a_star, f_calls + f_up, g_calls + g_up
        end

        # Evaluate phi'(a_i)
        d.g!(x_new, gr_new)
        g_calls += 1
        phiprime_a_i = dot(gr_new, p)

        # Check condition 2
        if abs(phiprime_a_i) <= -c2 * phiprime_0
            verbose && println("Condition 2")
            return a_i, f_calls, g_calls
        end

        # Check condition 3
        if phiprime_a_i >= 0.0
            verbose && println("Zoom for condition 3")
            a_star, f_up, g_up = zoom(a_i, a_iminus1,
                                      phiprime_0, phi_0,
                                      d.f, d.g!, x, p, x_new, gr_new, verbose=verbose)
            return a_star, f_calls + f_up, g_calls + g_up
        end

        # Choose a_iplus1 from the interval (a_i, a_max)
        a_iminus1 = a_i
        a_i *= rho

        # Update phi_a_iminus1
        phi_a_iminus1 = phi_a_i

        # Update iteration count
        i += 1
    end

    # Quasi-error response
    return a_max, f_calls, g_calls
end

function zoom(a_lo::Real,
              a_hi::Real,
              phiprime_0::Real,
              phi_0::Real,
              f::Function,
              g!::Function,
              x::Vector,
              p::Vector,
              x_new::Vector,
              gr_new::Vector;
              c1::Real = 1e-4,
              c2::Real = 0.9,
              verbose::Bool = false,
              max_iterations::Int64 = 10)

    # Parameter space
    n = length(x)

    # Count function and gradient calls
    f_calls, g_calls = 0, 0

    # Step-size
    a_j = NaN

    # Count iterations
    iteration = 0

    rho = 2.0

    @assert !isnan(f(x))

    # Shrink bracket
    while iteration < max_iterations
        verbose && println("Zoom iteration $iteration")
        iteration += 1

        # Cache phi_a_lo
        for index in 1:n
            x_new[index] = x[index] + a_lo * p[index]
        end
        phi_a_lo = f(x_new)
        verbose && println("phi_a_lo = $phi_a_lo")
        g!(x_new, gr_new)
        f_calls += 1
        g_calls += 1
        phiprime_a_lo = dot(gr_new, p)

        # Cache phi_a_hi
        for index in 1:n
            x_new[index] = x[index] + a_hi * p[index]
        end
        phi_a_hi = f(x_new)
        verbose && println("phi_a_hi = $phi_a_hi")
        g!(x_new, gr_new)
        f_calls += 1
        g_calls += 1
        phiprime_a_hi = dot(gr_new, p)

        # Interpolate a_j
        if isnan(phi_a_hi)
          a_hi /= rho
          a_j = a_hi
          println("Scaling back by rho.  $a_j")
        elseif a_lo < a_hi
            a_j = interpolate(a_lo, a_hi,
                              phi_a_lo, phi_a_hi,
                              phiprime_a_lo, phiprime_a_hi)
        else
            # TODO: Check if this is needed
            a_j = interpolate(a_hi, a_lo,
                              phi_a_hi, phi_a_lo,
                              phiprime_a_hi, phiprime_a_lo)
        end

        # Update x_new
        for index in 1:n
            x_new[index] = x[index] + a_j * p[index]
        end

        # Evaluate phi(a_j)
        phi_a_j = f(x_new)
        f_calls += 1

        # Check Armijo
        if isnan(phi_a_j)
            a_j /= rho
            a_hi = a_j
            verbose && println("Armijo scaling back by rho.  $a_j")
        elseif (phi_a_j > phi_0 + c1 * a_j * phiprime_0) ||
             (phi_a_j > phi_a_lo)
            verbose && println("Reducing a_hi")
        else
            # Evaluate phiprime(a_j)
            g!(x_new, gr_new)
            g_calls += 1
            phiprime_a_j = dot(gr_new, p)

            if abs(phiprime_a_j) <= -c2 * phiprime_0
                verbose && println("Zoom return Armijo.")
                return a_j, f_calls, g_calls
            end

            if phiprime_a_j * (a_hi - a_lo) >= 0.0
                verbose && println("setting a_hi = a_lo")
                return a_j, f_calls, g_calls
                #a_hi = a_lo # I don't get why this doesn't return here.
            end

            a_lo = a_j
        end
    end

    verbose && println("Zoom iters exceeded.")
    # Quasi-error response
    return a_j, f_calls, g_calls
end

# a_lo = a_{i - 1}
# a_hi = a_{i}
function interpolate(a_i1::Real, a_i::Real,
                     phi_a_i1::Real, phi_a_i::Real,
                     phiprime_a_i1::Real, phiprime_a_i::Real)
    d1 = phiprime_a_i1 + phiprime_a_i -
           3.0 * (phi_a_i1 - phi_a_i) / (a_i1 - a_i)
    d2 = sqrt(d1 * d1 - phiprime_a_i1 * phiprime_a_i)
    return a_i - (a_i - a_i1) *
            ((phiprime_a_i + d2 - d1) /
             (phiprime_a_i - phiprime_a_i1 + 2.0 * d2))
end
