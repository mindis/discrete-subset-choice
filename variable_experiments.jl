include("variable.jl")

function variable_model_freq_improvements(data::VariableChoiceDataset,
                                          num_updates::Int64,
                                          basename::AbstractString)
    # Vector for randomly splitting into training / test data
    n = length(data.choice_sizes)
    inds = collect(1:n)
    shuffle!(inds)
    num_folds = 10
    log_likelihoods = zeros(Float64, num_updates + 1, num_folds)
    
    for fold in 1:num_folds
        println(@sprintf("fold %d of %d", fold, num_folds))

        # Split into training / test data
        training = ones(Int64, n)
        fold_size = convert(Int64, floor(n / num_folds))
        test_start_ind = (fold - 1) * fold_size + 1
        test_end_ind = fold * fold_size
        if fold == num_folds; test_end_ind = n; end

        training[test_start_ind:test_end_ind] = 0
        training = training[inds]
        training_slate_sizes = Int64[]
        training_slates = Int64[]        
        training_choice_sizes = Int64[]
        training_choices = Int64[]
        test_slate_sizes = Int64[]
        test_slates = Int64[]        
        test_choice_sizes = Int64[]
        test_choices = Int64[]

        slate_inds = index_points(data.slate_sizes)
        choice_inds = index_points(data.choice_sizes)
        for ind = 1:length(data.choice_sizes)
            slate = data.slates[slate_inds[i]:(slate_inds[i + 1] - 1)]        
            choice = data.choices[choice_inds[i]:(choice_inds[i + 1] - 1)]
            if training[ind] == 1
                push!(training_slate_sizes, slate_size)
                append!(training_slates, slate)
                push!(training_choice_sizes, choice_size)
                append!(training_choices, choice)
            else
                push!(test_slate_sizes, slate_size)
                append!(test_slates, slate)
                push!(test_choice_sizes, choice_size)
                append!(test_choices, choice)
            end
        end
        training_data =
            VariableChoiceDataset(training_slate_sizes, training_slates,
                                  training_choice_sizes, training_choices)
        test_data =
            VariableChoiceDataset(test_slate_sizes, test_slates,
                                  test_choice_sizes, test_choices)
        model = initialize_model(training_data)        
        log_likelihoods[1, fold] = log_likelihood(model, test_data)

        choice_inds = index_points(training_data.choice_sizes)
        for i = 1:length(training_data.choice_sizes)
            choice = training_data.choices[choice_inds[i]:(choice_inds[i + 1] - 1)]
            for item in choice; item_counts[item] += 1; end
        end

        counts = [(count, choice_tup) for (choice_tup, count) in get_subset_counts(training_data)]
        sort!(counts, rev=true)
        choices_to_add = [collect(choice_tup) for (count, choice_tup) in counts[1:num_updates]]

        for (i, choice) in enumerate(choices_to_add)
            println(@sprintf("iteration %d of %d", i, num_updates))
            add_to_hotset_and_retrain!(model, choice, training_data)
            log_likelihoods[i + 1, fold] = log_likelihood(model, test_data)
        end
    end

    output = open("output/$basename-freq.txt", "w")
    for i = 0:num_updates
        write(output, @sprintf("%d %s\n", i, join(log_likelihoods[i + 1, :], " ")))
    end
end


function variable_model_frequency_experiments()
    function run(dataset_file::AbstractString)
        data = read_data(dataset_file)
        basename = split(split(dataset_file, "/")[end], ".")[1]
        num_items = length(unique(data.choices))
        num_updates = min(num_items, 1000)
        variable_model_freq_improvements(data, num_updates, basename)
    end

    run("data/yc-cats-5-5.txt")
    #run("data/yc-items-5-5.txt")    
end

variable_model_frequency_experiments()