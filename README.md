# discrete-subset-choice

This repository accompanies the paper

- Austin R. Benson, Ravi Kumar, and Andrew Tomkins. A Discrete Choice Model for Subset Selection. Proceedings of the eleventh ACM International Conference on Web Search and Data Mining (WSDM), 2018.

We include Julia implementations of the algorithms and the datasets used in the paper. We also provide scripts for re-producing the figures and tables as well as re-producing the experimental results.

Update August 27, 2018: The code has been updated to be compatible with Julia 1.0.

## Universal choice sets

Compute summary statistics of datasets (Table 1):
```
julia universal_statistics.jl
```

Reproduce figures (in the Julia REPL):
```julia
include("universal_figures.jl")
universal_likelihood_gains_plots()  # Figure 1 (universal-gains-*.eps)
negative_corrections_plot()  # Figure 2 (negative_corrections.eps)
```

Re-run experiments (commands here for specific datasets and to be run in the Julia REPL):
```julia
include("universal_experiments.jl")

# data for Figure 1 (output/bakery-5-25-{freq,lift,nlift}.txt)
universal_likelihood_experiments("bakery-5-25")

# data for Figure 2 
negative_corrections_experiment("walmart-items-5-25")  

# data for Table 2 (output/kosarak-5-25-times.txt)
timing_experiment("kosarak-5-25")  

# data for Table 3 (output/lastfm-genres-5-25-biggest-corrections.txt)
biggest_corrections_experiment("lastfm-genres-5-25")  
```

Example usage of model:
```julia
include("universal.jl")
data = read_data("data/bakery-5-25.txt")
for (size, choice) in iter_choices(data) # iterate over all subset selections
	println("$size, $choice")
end
model = initialize_model(data)
model.probs[6]  # item probability of item 6
model.gammas  # normalization constants
add_to_H!(model, [6, 14, 24])  # add element to H
model.probs[6]
```

## Variable choice sets

Compute summary statistics of datasets (most of Table 4):
```bash
julia variable_statistics.jl
```

Reproduce figures (in Julia REPL):
```julia
include("variable_figures.jl")
variable_likelihood_gains_plot()  # Figure 3
```

Re-run experiments (in Julia REPL):
```julia
include("variable_experiments.jl")
variable_likelihood_experiment("yc-cats-5-10-4-8.txt")
variable_likelihood_experiment("yc-items-5-10-4-8.txt")
```

## Data

The file `data/bakery.txt` contains the data for the bakery dataset (without any preprocessing).
Each line of the file is a subset selection from the universal choice set, and the universal choice set consists of all items that appear in at least one subset selection.
For example, the command `head data/bakery.txt` should produce the output
```
1 2
3 1 4 5
6 7 8
9 10 11 12
13 14 8
15 16 17
18 19 20 21
15 6 22 17
14 20 23 24 25
26 5
```
The first subset selection is {1, 2}, the second is {3, 1, 4, 5}, etc.
The file `data/bakery-5-25.txt` is a subset of `data/bakery.txt`, where all subset selections contain at most 5 items and all items appear in at least 25 subset selections.
Replacing "bakery" with "instacart", "kosarak", "lastfm-genres", "walmart-depts", or "walmart-items" gives the other universal choice set datasets.
The items in these datasets are codified by integers.
The real items are provided for the walmart-depts, instacart, and lastfm-genres datasets.
For example, running `head data/lastfm-genres-labels.txt` should give the output
```
1 rock
2 seen_live
3 indie
4 alternative
5 metal
6 electronic
7 punk
8 pop
9 indie_rock
10 classic_rock
```
This means that item "1" in the lastfm-genres dataset corresponds to "rock", item "2" corresponds to "seen_live", etc.

The file `data/yc-items.txt` contains the data for the YOOCHOOSE items dataset.
Each line of the file consists of two parts---separated by a semicolon---representing the (variable) choice set and the subset selection.
For example, the command `head data/yc-items.txt` should produce the output
```
30774 12821 3147;30774 3147
16109 26266 26267 28460;28460 16109
10590 2862 5051;2862
7168 5121;5121
1380 28325 26267 26264 23644;28325 26264
1214 662 1313;662
2867 3341 4754 1232 656;656 2867 3341
40664 36424 36423 36421 36428 40656 28348 4836 30754 249 3465 182 705;36424 40664 36428 36421 36423 40656 4836 30754 249
9673 59 122 7608 13340 13262 10626 501 3229 12407 7070;122 13340 13262 10626
44589 44592 44617 44616 44141 44591 44621 44586 37878 44618 44631 40665 44620 45254 26266 815;44616 44586 37878 44141 45254 44620 26266
```
In this case, the first choice set is {30774, 12821, 3147} and the subset selection is {30774, 3147}.
The set of items to the right of the semicolon (the subset selection) is always a subset of the items to the left of the semicolon (the choice set).

The file `data/yc-items-5-10-4-8.txt` represents a subset of the original dataset where every subset selection is of
size at most 5, every choice set is of size at most 10, every item is selected in a subset at least 4 times, and every
item appears in a choice set at least 8 times.
The experiments in the paper used this restricted dataset.

Replacing "yc-items" with "yc-cats" gives the YOOCHOOSE categories dataset.


### Citations for data

If you use our discrete subset choice datasets, please cite our paper:
```
@inproceedings{Benson-2018-subset,
title={A Discrete Choice Model for Subset Selection},
author = {Benson, Austin R. and Kumar, Ravi and Tomkins, Andrew},
booktitle={Proceedings of the eleventh ACM International Conference on Web Search and Data Mining (WSDM)},
year={2018},
organization={ACM}
}
```

If you use the Instacart data, please also cite the following:
```
@misc{instacart-data,
author={Instacart},
title={{The Instacart Online Grocery Shopping Dataset}},
howpublished={\url{https://www.instacart.com/datasets/grocery-shopping-2017}},
year={2017}
}
```

If you use the Lastfm data, please also cite the following
```
@misc{lastfm1k-data,
title = {{Last.fm Dataset -- 1K users}},
howpublished={\url{http://www.dtic.upf.edu/~ocelma/MusicRecommendationDataset/lastfm-1K.html}},
author = {Celma, O.},
year = {2010}
}

@misc{lastfmtags-data,
title = {{LastFM-ArtistTags2007} dataset},
howpublished = {\url{http://musicmachinery.com/2010/11/10/lastfm-artisttags2007/}},
author = {Paul Lamere},
year = {2008}
}
```
