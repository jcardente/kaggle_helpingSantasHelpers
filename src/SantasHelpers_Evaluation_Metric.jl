# ============================================================
# SantasHelpers_Evaluation_Metric.jl
#
# Julia port of the sample NaiveSolution to the
# Helping Santa's Helpers Kaggle Challenge. Original
# Python code available at:
#
# https://github.com/noahvanhoucke/HelpingSantasHelpers
#
# John Cardente, 2014
# ============================================================

using hrs
using toys
using elfs
using ArgParse


function read_toys(toy_file, num_toys)
    toysfile = open(toy_file, "r")
    readline(toysfile)
    
    toy_dict   = Dict()
    while !eof(toysfile)
        row = split(strip(readline(toysfile)),",")
        new_toy = Toy(row[1], row[2], row[3])
        toy_dict[new_toy.id] = new_toy
    end
    
    if (length(toy_dict) != num_toys)
        error("\n ** Read a file with $(length(toy_dict)) toys, expected $(num_toys). Exiting.\n")
        exit(-1)
    end
    
    toy_dict
end
    
function score_submission(sub_file, myToys, NUM_ELVES)
    myElves       = Dict()
    complete_toys = Int[]
    last_minute   = 0
    row_count     = 0

    fcsv = open(sub_file, "r")
    readline(fcsv)
    while !eof(fcsv)
        row_count += 1
        if (row_count % 50000) == 0
           print("Starting toy: $row_count\n")
        end

        row = split(strip(readline(fcsv)),",")
        current_toy  = int(row[1])
        current_elf  = int(row[2])
        start_minute = hrs.convert_to_minute(row[3])
        duration     = int(row[4])

        if !haskey(myToys, current_toy)
            error("Toy $(current_toy) not in toy dictionary\n")
            exit(-1)
        end

        if myToys[current_toy].completed_minute > 0
            error("Toy $(current_toy) was completed in minute $(myToys[current_toy].completed_minute)\n")
            exit(-1)
        end

        if !((1 <= current_elf) && (current_elf <= NUM_ELVES))
            error("\n ** Assigned elf does not exist: Elf $(current_elf)\n")
            exit(-1)
        end

        if !haskey(myElves, current_elf)
           myElves[current_elf] = elfs.Elf(current_elf)
        end

        if toys.outside_toy_start_period(myToys[current_toy], start_minute)
            error("\n ** Requestion work on Toy $(current_toy) at minute $(start_minute): Work can start at $(myToys[current_toy].arrival_minute)\n")
            exit(-1)
        end

        if start_minute < myElves[current_elf].next_available_time
            error("\n ** Elf $(current_elf) needs his rest, he is not available now $(start_minute) but will be later at $(myElves[current_elf].next_available_time), toy $(current_toy) rating  $(myElves[current_elf].rating)\n")
            exit(-1)
        end

        if !(toys.is_complete(myToys[current_toy], start_minute, duration, myElves[current_elf].rating))
            error("Toy $(current_toy) is not complete\n $(start_minute) $(duration) $(myElves[current_elf].rating)\n")
            exit(-1)
        else
            append!(complete_toys, [int(current_toy)])
            if myToys[current_toy].completed_minute > last_minute
                last_minute = myToys[current_toy].completed_minute
            end
        end

        old_rating = myElves[current_elf].rating
        elfs.update_elf(myElves[current_elf], myToys[current_toy], start_minute, duration)

    end

    if length(complete_toys) != length(myToys)
        error("\n ** Not all toys are complete. Exiting\n")
        exit(-1)
    end

    if maximum(complete_toys) != NUM_TOYS
        error("\n ** max ToyId != NUM_TOYS.\n")
        error("\n max(complete_toys) = $(max(complete_toys)) versus NUM_TOYS = $(NUM_TOYS)\n")
        exit(-1)
    end

    score = last_minute * log(1.0 + length(myElves))
    println("\nSuccess!")
    @printf("Last Minute = %d Score = %.02f\n", last_minute, score)
end




# ============================================================
# MAIN

s = ArgParseSettings()
@add_arg_table s begin
    "--nelves", "-e"
        help = "Number of elves"
        arg_type = Int
        default = 900
    "--ntoys", "-t"
        help = "Number of toys"
        arg_type = Int
        default = 10000000
    "toy_file"
        help = "Toy input file"
        required = true
    "soln_file"
        help = "Solution output file"
        required = true
end

parsed_args = parse_args(s)

NUM_TOYS  = parsed_args["ntoys"]
NUM_ELVES = parsed_args["nelves"]
toy_file  = parsed_args["toy_file"]
sub_file  = parsed_args["soln_file"]
start     = time()

print(" -- Reading toys file $(toy_file)\n")
myToys = read_toys(toy_file, NUM_TOYS)

print(" -- All toys read. Starting to score submission $(sub_file)\n")
score_submission(sub_file, myToys, NUM_ELVES)

elapsed_time = time() - start
print("total runtime = $elapsed_time\n")


