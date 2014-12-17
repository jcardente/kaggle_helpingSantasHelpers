
using hrs
using toys
using elfs
using ArgParse

# ============================================================
# TOYS

function read_toys(toy_file)
    toysfile = open(toy_file, "r")
    readline(toysfile)

    toy_queue   = Collections.PriorityQueue{Toy, Int}()
    while !eof(toysfile)
        row = split(strip(readline(toysfile)),",")
        new_toy = Toy(row[1], row[2], row[3])
        Collections.enqueue!(toy_queue, new_toy, new_toy.arrival_minute)
    end
    
    ## if (length(toy_queue) != num_toys)
    ##     error("\n ** Read a file with $(length(toy_queue)) toys, expected $(num_toys). Exiting.\n")
    ##     exit(-1)
    ## end
    
    toy_queue
end


function best_start_window(work_duration)
  #local work_duration = int(ceil(duration / rating))

 if (work_duration < (hrs._minutes_in_24h))    
    # NB - Pick window that ensures rating adjustment
    #      is one or greater
    max_unsanctioned = int(floor(0.165 * work_duration))
    min_sanctioned   = work_duration - max_unsanctioned
    best_start       = hrs._day_start
    best_end         = hrs._day_end -1 - min_sanctioned
  else
    # Pick window that maximizes the number of sanctioned
    # hours.
    work_duration     = work_duration % hrs._minutes_in_24h
    best_start       = hrs._day_start
    best_end         = max(hrs._day_start,
                           hrs._day_end -1 - min(hrs._hours_per_day * 60, work_duration))
  end

(best_start, best_end)
end


# ============================================================
# ELVES

function scale_rating(rating, sanctioned, unsanctioned)
 max(0.25,
    min(4.0, rating * (elfs._rating_increase ^ (sanctioned/60.0)) *
            (elfs._rating_decrease ^ (unsanctioned/60.0))))
end

## function create_elves(NUM_ELVES::int)
##     local list_elves
##     list_elves = Collections.PriorityQueue{Elf, Tuple}()
##     for i in 1:NUM_ELVES
##         _elf = Elf(i)
##         Collections.enqueue!(list_elves, _elf, (_elf.next_available_time, _elf.id))
##     end
    
##     list_elves
## end

function create_elves(coefs) #::Array{(Float64, Float64, Float64)})
    local list_elves
    list_elves = Collections.PriorityQueue{Elf, Tuple}()
    for i in 1:length(coefs)
        _elf = Elf(i, coefs[i][1], coefs[i][2], coefs[i][3])
        Collections.enqueue!(list_elves, _elf, (_elf.next_available_time, _elf.id))
    end

    println("Created $(length(list_elves)) elves")
    list_elves
end



function assign_elf_to_toy(input_time, current_elf, current_toy)
    start_time = next_sanctioned_minute(input_time)
    duration   = int(ceil(current_toy.duration / current_elf.rating))
    sanctioned, unsanctioned = get_sanctioned_breakdown(start_time, duration)

    if unsanctioned == 0
        return next_sanctioned_minute(start_time + duration), duration
    end
    apply_resting_period(start_time + duration, unsanctioned), duration
end


# ============================================================
# SCORING

function score_toy(current_toy, current_elf) 
  elf_start     = current_elf.next_available_time % hrs._minutes_in_24h
  work_duration = int(ceil(current_toy.duration / current_elf.rating))

  # XXX - convert to a lookup table to speed computations
  best_start, best_end = best_start_window(work_duration)
  score = 0
  if (best_start <= elf_start <= best_end)

      start_minute = max(best_start, elf_start)
      wait_time    = max(0, start_minute - elf_start)
      sanctioned, unsanctioned = get_sanctioned_breakdown(start_minute,work_duration)

      effective_prod  = (current_toy.duration) /
                        (sanctioned + 2*unsanctioned + wait_time)

      new_rating      = scale_rating(current_elf.rating,
                                     sanctioned,
                                     unsanctioned)
      
      # At the end of this toy, how close will we be to the maximum
      # productivity?
      scaled_rating   =  new_rating / 4
      
      # How close to ideal productivity will we be?
      scaled_prod     = (current_toy.duration/4) / effective_prod

      # How big of a job? Third quantile job size is 468 minutes, so consider
      # anything that takes a full day of sanctioned time as a big job.
      scaled_jobsize  = min(1.0, (work_duration) / (hrs._hours_per_day * 60))

      # Compute score based on Elf's coefficients      
      score = (current_elf.coef_rating   * scaled_rating +
               current_elf.coef_prod     * scaled_prod   +
               current_elf.coef_jobsize  * scaled_jobsize)
  end

  score
end

function find_best_toy(current_elf, toys)
  # Score the toys and take the best one
  scores = [score_toy(t, current_elf) for t in toys] ./ current_elf.rating
  first(findin(scores, maximum(scores)))
end



# ============================================================
# EVENT LOOP


function event_loop(toy_file, soln_file, elf_coefs)

    myToys  = read_toys(toy_file)
    #myElves = create_elves(num_elves)
    myElves = create_elves(elf_coefs)

    num_elves = length(myElves)
    
    wcsv     = open(soln_file, "w")
    write(wcsv,"ToyId,ElfId,StartTime,Duration\n");

    local last_minute = 0
    local prev_time   = 0
    local available_toys = Toy[]
    local completed_toys = Toy[]
    while((length(myToys) + length(available_toys)) > 0)

        # Get next elf
        current_elf  = Collections.dequeue!(myElves)
        current_time = current_elf.next_available_time

        # Update list of available toys
        if (current_time > prev_time)
            while (length(myToys) > 0 &&
                   Collections.peek(myToys)[1].arrival_minute <= current_time)
               push!(available_toys, Collections.dequeue!(myToys))
            end
        end

        # Find the best toy
        best_toy       = find_best_toy(current_elf, available_toys)
        current_toy    = available_toys[best_toy]
        available_toys = Collections.deleteat!(available_toys, best_toy)
        
        # Assign the elf
        work_start_time = current_time
        work_duration   = int(ceil(current_toy.duration / current_elf.rating))        
        update_elf(current_elf, current_toy, work_start_time, work_duration)
        
        # write to file in correct format
        tt = hrs._reference_start_time + Dates.Minute(work_start_time)
        time_string = join(map(string,[Dates.year(tt) Dates.month(tt) Dates.day(tt) Dates.hour(tt) Dates.minute(tt)]), " ")
        println(wcsv,current_toy.id,",",current_elf.id,",",time_string,",",work_duration)

        # Add elf to event queue
        Collections.enqueue!(myElves, current_elf, (current_elf.next_available_time,
                                                    current_elf.id))
        
        # Update time
        last_minute = max(last_minute, work_start_time + work_duration)
        prev_time = current_time
    end
    close(wcsv)

    avg_prod = sum([e.rating for (e,v) in myElves]) / num_elves
    
    return num_elves, last_minute, avg_prod
end



# ============================================================
# MAIN

s = ArgParseSettings()
@add_arg_table s begin
    "--nelves", "-e"
        help = "Number of elves"
        arg_type = Int
        default = 900
    "toy_file"
        help = "Toy input file"
        required = true
    "soln_file"
        help = "Solution output file"
        required = true
end

parsed_args = parse_args(s)

start     = time()
NUM_ELVES = parsed_args["nelves"]
toy_file  = parsed_args["toy_file"]
soln_file = parsed_args["soln_file"]

elf_coefs = repmat([(1.0, 0, 0); (0, 1.0, 0); (0,0,1.0)],
                   int(NUM_ELVES/3), 1)

num_elves, last_minute, avg_prod = event_loop(toy_file, soln_file, elf_coefs)

elapsed_time = time() - start
score = last_minute * log(1.0 + num_elves)

@printf("Runtime= %.2f \tScore= %d \tProd=%.2f\t LastMin=%d\n",
        elapsed_time, score, avg_prod, last_minute)
        
