include("util.jl")

using StatsBase
using Base.Test

function in_hotset(choice::Vector{Int64}, model::UniversalChoiceModel)
    choice_size = length(choice)
    key = NTuple{choice_size, Int64}(choice)
    return haskey(model.H[choice_size], key)
end

function hotset_prob(choice::Vector{Int64}, model::UniversalChoiceModel)
    choice_size = length(choice)
    key = NTuple{choice_size, Int64}(choice)
    return model.H[choice_size][key]
end

function log_likelihood(data::UniversalChoiceDataset, model::UniversalChoiceModel)
    ll = 0.0
    for (size, choice) in iter_choices(data)
        if in_hotset(choice, model)
            ll += hotset_prob(choice, model)
        else
            ll += log(model.gammas[length(choice)])
            for item in choice; ll += log(model.probs[item]); end
        end
    end
    return ll
end

function normalization_values(max_size::Int64, H::Vector{Dict{NTuple,Float64}},
                              item_probs::Vector{Float64})
    gammas = zeros(Float64, max_size)

    # No hotsets of size 1
    gammas[1] = 1

    if max_size == 1; return gammas; end
    # normalization for size-2 choice probabilities
    # 2 * sum_pipj + sum_pi2 = 1
    # gamma2 * (sum_pipj + sum_pi2) + hotset_probs2 = 1
    sum_pi2       = sum([p^2 for p in item_probs])
    sum_pipj      = (1 - sum_pi2) / 2
    hotset_probs2 = sum([val for (key, val) in H[2]])
    gammas[2]     = (1 - hotset_probs2) / (sum_pipj + sum_pi2)

    if max_size == 2; return gammas; end    
    # normalization for size-3 choice probabilities
    # 6 * sum_pipjpk + 3 * sum_pipjpj + sum_pi3 = 1
    # sum_pipjpj + sum_pi3 = sum_pi2
    # gamma * (sum_pipjpk + sum_pipjpj + sum_pi3) + hotset_probs3 = 1
    sum_pi3       = sum([p^3 for p in item_probs])
    sum_pipjpj    = sum_pi2 - sum_pi3
    sum_pipjpk    = (1 - sum_pi3 - 3 * sum_pipjpj) / 6
    hotset_probs3 = sum([val for (key, val) in H[3]])
    gammas[3]     = (1 - hotset_probs3) / (sum_pipjpk + sum_pipjpj + sum_pi3)

    if max_size == 3; return gammas; end
    # normalization for size-4 choice probabilities
    # 24 * sum_pipjpkpl + 6 * sum_pi2pj2 + 4 * sum_pipj3 + 12 * sum_pipjpk2 + sum_pi4 = 1
    # sum_pi2pj2 + sum_pi4 = (sum_pi2)^2
    # sum_pipj3 + sum_pi4 = sum_pi3
    # 2 * sum_pipjpk2 + 2 * sum_pipj3 + + 2 * sum_pi2pj2 + sum_pi4 = sum_pi2
    # gamma * (sum_pipjpkpl + sum_pi2pj2 + sum_pipj3 + sum_pipjpk2 + sum_pi4) + hotset_probs4 = 1
    sum_pi4       = sum([p^4 for p in item_probs])
    sum_pi2pj2    = (sum_pi2 ^ 2 - sum_pi4) / 2
    sum_pipj3     = sum_pi3 - sum_pi4
    sum_pipjpk2   = (sum_pi2 - sum_pi4 - 2 * sum_pipj3 - 2 * sum_pi2pj2) / 2    
    sum_pipjpkpl  = (1 - sum_pi4 - 4 * sum_pipj3 - 6 * sum_pi2pj2 - 12 * sum_pipjpk2) / 24    
    hotset_probs4 = sum([val for (key, val) in H[4]])
    gammas[4]     = (1 - hotset_probs4) / (sum_pipjpkpl + sum_pi2pj2 + sum_pipj3 + sum_pipjpk2 + sum_pi4)
    
    if max_size == 4; return gammas; end
    # normalization for size-5 choice probabilities
    sum_pi5       = sum([p^5 for p in item_probs])
    sum_pipj4     = sum_pi4 - sum_pi5
    sum_pi2pj3    = sum_pi2 * sum_pi3 - sum_pi5
    sum_pipjpk3   = (sum_pi3 - sum_pi5 - 2 * sum_pipj4 - sum_pi2pj3) / 2
    
    gammas[5] = 1
    
    # TODO: support larger sizes.  We really shouldn't hard code the above.
    # There is a triangular system we can solve to automatically determine these
    # values, but it is annoying to set up.
    if max_size > 5; error("Support only for choices of size <= 5 items"); end

    return gammas
end

function update_hotset_and_model(data::UniversalChoiceDataset, model::UniversalChoiceModel,
                                 choice_to_add::Vector{Int64})
    if in_hotset(choice_to_add, model); error("Choice already in hot set."); end

    choice_to_add_count = 0
    item_counts = zeros(Int64, maximum(data.choices))    
    for (size, choice) in iter_choices(data)
        if choice == choice_to_add;
            choice_to_add_count += 1
        elseif !in_hotset(choice, model)
            for item in choice
                item_counts[item] += 1
            end
        end
    end

    # Update hot set probability for the new choice
    lc = length(choice_to_add)
    model.H[lc][NTuple{lc, Int64}(choice_to_add)] = choice_to_add_count / length(data.sizes)
    # Update item counts
    total = sum(item_counts)
    for (i, count) in enumerate(item_counts); model.probs[i] = count / total; end
    # Update normalization parameters
    model.gammas = normalization_values(maximum(data.sizes), model.H, model.probs)
end

function initialize_model(data::UniversalChoiceDataset)
    max_size = maximum(data.sizes)

    # fixed-size probability are just the empirical fraction of selections
    z = zeros(Float64, max_size)
    for (key, value) in countmap(data.sizes); z[key] = value / length(data.sizes); end

    # item probabilities are initialized to the empirical fraction of
    # appearances in choice sets
    item_counts = zeros(Int64, maximum(data.choices))
    for (size, choice) in iter_choices(data)
        for item in choice; item_counts[item] += 1; end
    end
    item_probs = zeros(Float64, length(item_counts))
    total = sum(item_counts)
    for (i, count) in enumerate(item_counts); item_probs[i] = count / total; end

    # Initialize empty hotsets
    H = Vector{Dict{NTuple,Float64}}(max_size)
    for i in 1:max_size; H[i] = Dict{NTuple{i, Int64}, Float64}(); end

    gammas = normalization_values(max_size, H, item_probs)

    return UniversalChoiceModel(z, item_probs, gammas, H)
end

function update_by_frequency(data::UniversalChoiceDataset, num_updates::Int64)
    # Get the counts
    counts = Dict{NTuple, Int64}()
    for (size, choice) in iter_choices(data)
        choice_tup = NTuple{length(choice), Int64}(choice)
        if length(choice) > 1
            if !haskey(counts, choice_tup); counts[choice_tup] = 0; end
            counts[choice_tup] += 1
        end
    end
    counts = [(count, choice_tup) for (choice_tup, count) in counts]
    sort!(counts, rev=true)
    choices_to_add = [collect(choice_tup) for (count, choice_tup) in counts[1:num_updates]]
    @show choices_to_add

    model = initialize_model(data)
    lls = Float64[]
    push!(lls, log_likelihood(data, model))

    for (i, choice) in enumerate(choices_to_add)
        println(@sprintf("iteration %d of %d", i, num_updates))
        update_hotset_and_model(data, model, choice)
        #push!(lls, log_likelihood(data, model))        
    end
end

function test()
    data = read_data("data/bakery-5-10.txt")
    model = initialize_model(data)

    p = model.probs
    n = maximum(data.choices)
    @show n
    
    p1 = sum([val for (key, val) in model.H[1]])
    g = model.gammas[1]    
    for i = 1:n; p1 += g * p[i]; end
    @test p1 ≈ 1

    p2 = sum([val for (key, val) in model.H[2]])
    g = model.gammas[2]
    for i = 1:n; for j = i:n; p2 += g * p[i] * p[j]; end; end
    @test p2 ≈ 1    

    p3 = sum([val for (key, val) in model.H[3]])
    g = model.gammas[3]
    for i = 1:n; for j = i:n; for k = j:n; p3 += g * p[i] * p[j] * p[k]; end; end; end
    @test p3 ≈ 1    

    p4 = sum([val for (key, val) in model.H[4]])
    g = model.gammas[4]
    for i = 1:n; for j = i:n; for k = j:n; for l = k:n; p4 += g * p[i] * p[j] * p[k] * p[l]; end; end; end; end
    @test p4 ≈ 1    

    sum_pi2       = sum([v^2 for v in p])        
    sum_pi3       = sum([v^3 for v in p])    
    sum_pi4       = sum([v^4 for v in p])
    sum_pi5       = sum([v^5 for v in p])

    sum_pipj4     = sum_pi4 - sum_pi5
    test_pipj4 = 0.0
    for i = 1:n
        for j = 1:n
            if j != i
                test_pipj4 += p[i] * p[j]^4
            end
        end
    end
    @test test_pipj4 ≈ sum_pipj4

    sum_pi2pj3    = sum_pi2 * sum_pi3 - sum_pi5
    test_pi2pj3 = 0.0    
    for i = 1:n
        for j = 1:n
            if j != i
                test_pi2pj3 += p[i]^2 * p[j]^3
            end
        end
    end
    @test test_pi2pj3 ≈ sum_pi2pj3

    sum_pipjpk3   = (sum_pi3 - sum_pi5 - 2 * sum_pipj4 - sum_pi2pj3) / 2
    test_pipjpk3  = 0.0
    for i = 1:n
        for j = (i+1):n
            for k = 1:n
                if k != i && k != j
                    test_pipjpk3 += p[i] * p[j] * p[k]^3
                end
            end
        end
    end
    @test test_pipjpk3 ≈ sum_pipjpk3

    sum_pipj2pk2 = (sum_pi2^2 - sum_pipj4 - 2 * sum_pi2pj3 - sum_pi5) / 2
    test_pipj2pk2 = 0.0
    for i = 1:n
        for j = 1:n
            for k = (j+1):n
                if i != j && i != k
                    test_pipj2pk2 += p[i] * p[j]^2 * p[k]^2
                end
            end
        end
    end
    @test test_pipj2pk2 ≈ sum_pipj2pk2

    sum_pipjpkpl2 = (sum_pi2 - 3 * sum_pipjpk3) / 6
    test_pipjpkpl2 = 0.0
    for i = 1:n
        for j = (i+1):n
            for k = (j+1):n
                for l = 1:n
                    if l != i && l != j && l != k
                        test_pipjpkpl2 += p[i] * p[j] * p[k] * p[l]^2
                    end
                end
            end
        end
    end
    #@test test_pipjpkpl2 ≈ sum_pipjpkpl2

    sum_pipjpkplpm = (1 - 5 * sum_pipj4 - 10 * sum_pipjpk3 - 10 * test_pipjpkpl2 - 30 * sum_pipj2pk2) / 120
    test_pipjpkplpm = 0.0
    for i = 1:n
        for j = (i+1):n
            for k = (j+1):n
                for l = (k+1):n
                    for m = (l+1):n
                        test_pipjpkplpm += p[i] * p[j] * p[k] * p[l] * p[m]
                    end
                end
            end
        end
    end
    @test test_pipjpkplpm ≈ sum_pipjpkplpm
    
    p5 = sum([val for (key, val) in model.H[5]])
    g = model.gammas[5]
    for i = 1:n; for j = i:n; for k = j:n; for l = k:n; for m = l:n; p5 += g * p[i] * p[j] * p[k] * p[l] * p[m]; end; end; end; end; end
    @test p5 ≈ 1    
end

function main()
    data = read_data("data/bakery-5-10.txt")
    update_by_frequency(data, 100)
    #model = initialize_model(data)
    #@show model.z
    #@show model.probs
    #@show model.gammas
    #@show model.H
end

test()
