include("common.jl")
using StatsBase
using Base.Threads
using Optim

# Represent a variable choice dataset as a vector of slate sizes, a vector of
# all slates, a vector of choice set sizes, and a vector of all choices.
mutable struct VariableChoiceDataset
    slate_sizes::Vector{Int64}
    slates::Vector{Int64}
    choice_sizes::Vector{Int64}
    choices::Vector{Int64}
end

# Utility-based variable choice model.
#
# -z is a vector of length max_size with the probability of choosing
#  a size-k subset being z[k]
# -utilities are the item utilities
# -H is a vector of length max_size where each element
#  is a dictionary that maps a choice set to a utility.
mutable struct VariableChoiceModel
    z::Vector{Float64}
    utilities::Vector{Float64}
    H::Dict{NTuple,Float64}
end

function get_subset_counts(data::VariableChoiceDataset)
    # Get the counts
    counts = Dict{NTuple, Int64}()
    choice_inds = index_points(data.choice_sizes)
    for i = 1:length(data.choice_sizes)
        choice = data.choices[choice_inds[i]:(choice_inds[i + 1] - 1)]
        choice_tup = vec2ntuple(choice)
        if length(choice) > 1
            if !haskey(counts, choice_tup); counts[choice_tup] = 0; end
            counts[choice_tup] += 1
        end
    end
    return counts
end

# Read text data
function read_data(dataset::AbstractString)
    f = open(dataset)
    slate_sizes = Int64[]
    slates = Int64[]
    choice_sizes = Int64[]    
    choices = Int64[]
    for line in eachline(f)
        slate_choice = split(line, ";")
        slate = [parse(Int64, v) for v in split(slate_choice[1])]
        sort!(slate)
        choice = [parse(Int64, v) for v in split(slate_choice[2])]
        sort!(choice)
        push!(slate_sizes, length(slate))
        append!(slates, slate)
        push!(choice_sizes, length(choice))
        append!(choices, choice)
    end
    return VariableChoiceDataset(slate_sizes, slates, choice_sizes, choices)
end

# iterator over choices
function iter_slates_choices(data::VariableChoiceDataset)
    curr_slate_ind = 1
    curr_choice_ind = 1
    slate_vec = Vector{Vector{Int64}}()
    choice_vec = Vector{Vector{Int64}}()
    for (slate_size, choice_size) in zip(data.slate_sizes, data.choice_sizes)
        slate = data.slates[curr_slate_ind:(curr_slate_ind + slate_size - 1)]
        choice = data.choices[curr_choice_ind:(curr_choice_ind + choice_size - 1)]
        push!(slate_vec, slate)
        push!(choice_vec, choice)
        curr_slate_ind += slate_size
        curr_choice_ind += choice_size
    end
    assert(curr_slate_ind == length(data.slates) + 1)
    assert(curr_choice_ind == length(data.choices) + 1 )          
    return zip(data.slate_sizes, slate_vec, data.choice_sizes, choice_vec)
end

in_hotset(model::VariableChoiceModel, choice::Vector{Int64}) =
    haskey(model.H, vec2ntuple(choice))
hotset_utility(model::VariableChoiceModel, choice::Vector{Int64}) =
    model.H[vec2ntuple(choice)]

function hotset_val(model::VariableChoiceModel, choice::Vector{Int64})
    choice_size = length(choice)
    key = vec2ntuple(choice)
    if !haskey(model.H, key); return 0.0; end
    return model.H[key]
end

function set_hotset_value!(model::VariableChoiceModel, choice::Vector{Int64}, val::Float64)
    model.H[vec2ntuple(choice)] = val
end

function set_hotset_value!(model::VariableChoiceModel, choice::NTuple, val::Float64)
    model.H[choice] = val
end


function add_to_hotset!(model::VariableChoiceModel, choice_to_add::Vector{Int64})
    if in_hotset(model, choice_to_add); error("Choice already in hot set."); end
    set_hotset_value!(model, choice_to_add, 0.0)
end

function expsum_util1(model::VariableChoiceModel, slate::Vector{Int64})
    ns = length(slate)
    total = 0.0
    for ind_i = 1:ns
        i = slate[ind_i]
        total += exp(model.utilities[i])
    end
    return total
end

function expsum_util2(model::VariableChoiceModel, slate::Vector{Int64})
    ns = length(slate)
    total = 0.0
    subset = [0, 0]
    for ind_i = 1:ns
        i = slate[ind_i]
        subset[1] = i
        si = model.utilities[i]
        for ind_j = ind_i:ns
            j = slate[ind_j]
            subset[2] = j
            sj = si + model.utilities[j] + hotset_val(model, subset)
            total += exp(sj)
        end
    end
    return total
end

function expsum_util3(model::VariableChoiceModel, slate::Vector{Int64})
    ns = length(slate)
    total = 0.0
    subset = [0, 0, 0]
    for ind_i = 1:ns
        i = slate[ind_i]        
        subset[1] = i
        si = model.utilities[i]
        for ind_j = ind_i:ns
            j = slate[ind_j]            
            subset[2] = j
            sj = si + model.utilities[j]
            for ind_k = ind_j:ns
                k = slate[ind_k]
                subset[3] = k
                sk = sj + model.utilities[k] + hotset_val(model, subset)
                total += exp(sk)
            end
        end
    end
    return total
end

function expsum_util4(model::VariableChoiceModel, slate::Vector{Int64})
    ns = length(slate)
    total = 0.0
    subset = [0, 0, 0, 0]
    for ind_i = 1:ns
        i = slate[ind_i]
        subset[1] = i
        si = model.utilities[i]
        for ind_j = ind_i:ns
            j = slate[ind_j]
            subset[2] = j
            sj = si + model.utilities[j]
            for ind_k = ind_j:ns
                k = slate[ind_k]                
                subset[3] = k
                sk = sj + model.utilities[k]
                for ind_l = ind_k:ns
                    l = slate[ind_l]                    
                    subset[4] = l
                    sl = sk + model.utilities[l] + hotset_val(model, subset)
                    total += exp(sl)
                end
            end
        end
    end
    return total
end

function expsum_util5(model::VariableChoiceModel, slate::Vector{Int64})
    ns = length(slate)
    total = 0.0
    subset = [0, 0, 0, 0, 0]
    for ind_i = 1:ns
        i = slate[ind_i]        
        subset[1] = i
        si = model.utilities[i]
        for ind_j = ind_i:ns
            j = slate[ind_j]
            subset[2] = j
            sj = si + model.utilities[j]
            for ind_k = ind_j:ns
                k = slate[ind_k]
                subset[3] = k
                sk = sj + model.utilities[k]
                for ind_l = ind_k:ns
                    l = slate[ind_l]
                    subset[4] = l
                    sl = sk + model.utilities[l]
                    for ind_m = ind_l:ns
                        m = slate[ind_m]
                        subset[5] = m
                        sm = sl + model.utilities[m] + hotset_val(model, subset)
                        total += exp(sm)
                    end
                end
            end
        end
    end
    return total
end

function gradient_update1!(model::VariableChoiceModel, slate::Vector{Int64},
                           grad::Vector{Float64})
    sum = expsum_util1(model, slate)
    if isnan(sum)
        @show slate
        @show model.utilities[slate[1]]
        @show exp(model.utilities[slate[1]])
    end
    assert(!isnan(sum))
    ns = length(slate)
    for ind_i = 1:ns
        i = slate[ind_i]
        grad[i] += exp(model.utilities[i]) / sum
    end
end

function gradient_update2!(model::VariableChoiceModel, slate::Vector{Int64},
                           grad::Vector{Float64}, hotset_inds::Dict{NTuple, Int64})
    sum = expsum_util2(model, slate)
    assert(!isnan(sum))    
    ns = length(slate)
    subset = [0, 0]
    for ind_i = 1:ns
        i = slate[ind_i]
        subset[1] = i
        si = model.utilities[i]
        for ind_j = ind_i:ns
            j = slate[ind_j]            
            subset[2] = j
            sj = si + model.utilities[j] + hotset_val(model, subset)
            grad[subset] += exp(sj) / sum
            if in_hotset(model, subset)
                grad[hotset_inds[vec2ntuple(subset)]] += exp(sj) / sum
            end
        end
    end
end

function gradient_update3!(model::VariableChoiceModel, slate::Vector{Int64},
                           grad::Vector{Float64}, hotset_inds::Dict{NTuple, Int64})
    sum = expsum_util3(model, slate)
    assert(!isnan(sum))    
    ns = length(slate)
    subset = [0, 0, 0]
    for ind_i = 1:ns
        i = slate[ind_i]        
        subset[1] = i
        si = model.utilities[i]
        for ind_j = ind_i:ns
            j = slate[ind_j]            
            subset[2] = j
            sj = si + model.utilities[j]
            for ind_k = ind_j:ns
                k = slate[ind_k]
                subset[3] = k
                sk = sj + model.utilities[k] + hotset_val(model, subset)
                grad[subset] += exp(sk) / sum
                if in_hotset(model, subset)
                    grad[hotset_inds[vec2ntuple(subset)]] += exp(sk) / sum
                end
            end
        end
    end
end

function gradient_update4!(model::VariableChoiceModel, slate::Vector{Int64},
                           grad::Vector{Float64}, hotset_inds::Dict{NTuple, Int64})
    sum = expsum_util4(model, slate)
    assert(!isnan(sum))    
    ns = length(slate)
    subset = [0, 0, 0, 0]
    for ind_i = 1:ns
        i = slate[ind_i]
        subset[1] = i
        si = model.utilities[i]
        for ind_j = ind_i:ns
            j = slate[ind_j]            
            subset[2] = j
            sj = si + model.utilities[j]
            for ind_k = ind_j:ns
                k = slate[ind_k]                
                subset[3] = k
                sk = sj + model.utilities[k]
                for ind_l = ind_k:ns
                    l = slate[ind_l]                    
                    subset[4] = l
                    sl = sk + model.utilities[l] + hotset_val(model, subset)
                    grad[subset] += exp(sl) / sum
                    if in_hotset(model, subset)
                        grad[hotset_inds[vec2ntuple(subset)]] += exp(sl) / sum
                    end
                end
            end
        end
    end
end

function gradient_update5!(model::VariableChoiceModel, slate::Vector{Int64},
                           grad::Vector{Float64}, hotset_inds::Dict{NTuple, Int64})
    sum = expsum_util5(model, slate)
    assert(!isnan(sum))
    ns = length(slate)
    subset = [0, 0, 0, 0, 0]
    for ind_i = 1:ns
        i = slate[ind_i]
        subset[1] = i
        si = model.utilities[i]
        for ind_j = ind_i:ns
            j = slate[ind_j]
            subset[2] = j
            sj = si + model.utilities[j]
            for ind_k = ind_j:ns
                k = slate[ind_k]
                subset[3] = k
                sk = sj + model.utilities[k]
                for ind_l = ind_k:ns
                    l = slate[ind_l]
                    subset[4] = l
                    sl = sk + model.utilities[l]
                    for ind_m = ind_l:ns
                        m = slate[ind_m]
                        subset[5] = m
                        sm = sl + model.utilities[m] + hotset_val(model, subset)
                        grad[subset] += exp(sm) / sum
                        if in_hotset(model, subset)
                            grad[hotset_inds[vec2ntuple(subset)]] += exp(sm) / sum
                        end
                    end
                end
            end
        end
    end
end


# Given a slate, takes the sum of the exponential of the set utilities for all
# size-k subsets of the slate.  There is one function for each of k = 1, 2, 3, 4, 5.
function expsum_util(model::VariableChoiceModel, slate::Vector{Int64}, size::Int64)
    if     size == 1; return expsum_util1(model, slate)
    elseif size == 2; return expsum_util2(model, slate)
    elseif size == 3; return expsum_util3(model, slate)
    elseif size == 4; return expsum_util4(model, slate)
    elseif size == 5; return expsum_util5(model, slate)
    else error(@sprintf("Cannot handle size %d", size))
    end
end

function update_gradient_from_slate!(model::VariableChoiceModel, grad::Vector{Float64}, slate::Vector{Int64},
                                     choice_size::Int64, hotset_inds::Dict{NTuple, Int64})
    if     choice_size == 1; gradient_update1!(model, slate, grad)
    elseif choice_size == 2; gradient_update2!(model, slate, grad, hotset_inds)
    elseif choice_size == 3; gradient_update3!(model, slate, grad, hotset_inds)
    elseif choice_size == 4; gradient_update4!(model, slate, grad, hotset_inds)
    elseif choice_size == 5; gradient_update5!(model, slate, grad, hotset_inds)
    else error(@sprintf("Cannot handle size %d", choice_size))
    end
end
        
function log_likelihood(model::VariableChoiceModel, data::VariableChoiceDataset)
    ns = length(data.slate_sizes)
    ll = zeros(Float64, ns)
    slate_inds = index_points(data.slate_sizes)
    choice_inds = index_points(data.choice_sizes)
    Threads.@threads for i = 1:ns    
        slate = data.slates[slate_inds[i]:(slate_inds[i + 1] - 1)]        
        choice = data.choices[choice_inds[i]:(choice_inds[i + 1] - 1)]
        size = length(choice)
        ll[i] += log(model.z[size])
        for item in choice; ll[i] += model.utilities[item]; end
        ll[i] += hotset_val(model, choice)
        ll[i] -= log(expsum_util(model, slate, size))
    end
    return sum(ll)
end

function learn_utilities!(model::VariableChoiceModel, data::VariableChoiceDataset)
    n_items = length(model.utilities)
    hotset_tups = Vector{NTuple}()
    hotset_inds = Dict{NTuple, Int64}()
    hotset_vals = Float64[]
    for (tup, val) in model.H
        push!(hotset_tups, tup)
        hotset_inds[tup] = n_items + length(hotset_tups)
        push!(hotset_vals, val)
    end
    
    function update_model!(x::Vector{Float64})
        # Vector x contains item utilities and hotset utilities
        x[find(isnan.(x))] = 0.0
        model.utilities = copy(x[1:n_items])
        for (tup, val) in zip(hotset_tups, x[(n_items + 1):end])
            set_hotset_value!(model, tup, val)
        end
    end

    function neg_log_likelihood!(x::Vector{Float64})
        update_model!(x)
        return -log_likelihood(model, data)
    end

    slate_inds = index_points(data.slate_sizes)
    choice_inds = index_points(data.choice_sizes)
    function gradient!(grad::Vector{Float64}, x::Vector{Float64})
        for i = 1:length(x); grad[i] = 0.0; end
        update_model!(x)
        for i = 1:length(data.slate_sizes)
            slate = data.slates[slate_inds[i]:(slate_inds[i + 1] - 1)]        
            choice = data.choices[choice_inds[i]:(choice_inds[i + 1] - 1)]
            size = length(choice)
            for item in choice; grad[item] -= 1; end
            if in_hotset(model, choice)
                grad[hotset_inds[vec2ntuple(choice)]] -= 1
            end
            update_gradient_from_slate!(model, grad, slate, size, hotset_inds) 
        end
        (_, maxind) = findmax(x)
        grad[maxind] = 0.0
        gnorm = norm(grad, 2)
        for i = 1:length(x); grad[i] /= gnorm; end
    end

    nvars = length(model.utilities) + length(hotset_tups)
    options = Optim.Options(f_tol=1e-4, show_trace=true, show_every=1, extended_trace=true)
    #options = Optim.Options(f_tol=1e-6)
    x0 = [copy(model.utilities); hotset_vals]
    res = optimize(neg_log_likelihood!, gradient!, x0,
                   LBFGS(; linesearch=LineSearches.BackTracking()), options)
    update_model!(res.minimizer)
end

function learn_size_probs!(model::VariableChoiceModel, data::VariableChoiceDataset)
    function neg_log_likelihood(x::Vector{Float64})
        nll = 0.0
        for (slate_size, choice_size) in zip(data.slate_sizes, data.choice_sizes)
            nll -= x[choice_size]
            total = 0.0
            max_choice_size = min(slate_size - 1, length(x))            
            for i in 1:max_choice_size; total += exp(x[i]); end
            nll += log(total)
        end
        return nll
    end

    function gradient!(grad::Vector{Float64}, x::Vector{Float64})
        # Assume utility of first element is 0
        for i = 1:length(x); grad[i] = 0.0; end
        for (slate_size, choice_size) in zip(data.slate_sizes, data.choice_sizes)
            if choice_size > 1; grad[choice_size] -= 1; end
            total = 1.0
            max_choice_size = min(slate_size - 1, length(x))
            for i in 2:max_choice_size; total += exp(x[i]); end
            grad[2:max_choice_size] += exp.(x[2:max_choice_size]) / total
        end
    end

    options = Optim.Options(f_tol=1e-6, show_trace=true, show_every=1, extended_trace=true)    
    res = optimize(neg_log_likelihood, gradient!,
                   zeros(Float64, maximum(data.choice_sizes)), LBFGS(), options)
    model.z = exp.(res.minimizer) / sum(exp.(res.minimizer))
end

function initialize_model(data::VariableChoiceDataset)
    max_choice_size = maximum(data.choice_sizes)
    z = ones(Float64, max_choice_size) / max_choice_size
    utilities = zeros(Float64, maximum(data.slates))
    H = Dict{NTuple, Float64}()
    return VariableChoiceModel(z, utilities, H)
end

function learn_model!(model::VariableChoiceModel, data::VariableChoiceDataset)
    learn_size_probs!(model, data)
    @show model.z
    learn_utilities!(model, data)
end

function main()
    data = read_data("data/yc-items-5-5.txt")
    model = initialize_model(data)
    learn_model!(model, data)
    return model
end

#main()
