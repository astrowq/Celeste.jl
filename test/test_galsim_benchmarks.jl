using Base.Test

using DataFrames

import Celeste: GalsimBenchmark


if test_long_running
    GALSIM_CASES_EXERCISED = [
        "simple_star",
        "star_with_noise",
        "angle_and_axis_ratio_1",
        "galaxy_with_all",
        "galaxy_with_noise",
    ]
else
    GALSIM_CASES_EXERCISED = [
        "star_with_noise",
    ]
end


function assert_estimates_are_close(benchmark_results)
    for row in eachrow(benchmark_results)
        if ismissing(row[:truth])
            continue
        end
        if row[:variable] == :is_star
            maximum_error = 0.1
        elseif row[:variable] == :gal_frac_dev
            maximum_error = 0.2
        elseif row[:variable] == :gal_angle_deg
            maximum_error = 5
        else
            maximum_error = 0.2 * abs(row[:truth])
        end
        if !isapprox(row[:truth], row[:estimate], atol=maximum_error)
            @show row
            @show maximum_error
            @test false
        else
            @test true # just so test framework will count test cases
        end
    end
end

@testset "GalSim benchmark tests, single-source inference" begin
    truth, results = GalsimBenchmark.run_benchmarks(
        test_case_names=GALSIM_CASES_EXERCISED,
        joint_inference=false
    )
    assert_estimates_are_close(GalsimBenchmark.truth_comparison_df(truth, results))
end

@testset "GalSim benchmark tests, joint inference" begin
    truth, results = GalsimBenchmark.run_benchmarks(
        test_case_names=GALSIM_CASES_EXERCISED,
        joint_inference=true
    )
    assert_estimates_are_close(GalsimBenchmark.truth_comparison_df(truth, results))
end
