
using hrs
using toys
using elfs
using ArgParse

# ============================================================
# TOYS

function read_toys(toy_file)
    toysfile = open(toy_file, "r")
    readline(toysfile)

    toy_list = Dict()
    while !eof(toysfile)
        row = split(strip(readline(toysfile)),",")
        new_toy = Toy(row[1], row[2], row[3])
        #Collections.enqueue!(toy_queue, new_toy, new_toy.arrival_minute)
        toy_list[new_toy.id] = new_toy 
    end
      
    toy_list
end


function best_start_window(work_duration)
    
    if (work_duration > hrs._minutes_in_24h)
        work_duration = work_duration % hrs._minutes_in_24h
    end
    
    # NB - Pick window that ensures rating adjustment
    #      is one or greater
    max_unsanctioned = int(floor(0.165 * work_duration))
    min_sanctioned   = int(min(hrs._hours_per_day * 60, work_duration - max_unsanctioned))
    best_start       = hrs._day_start
    best_end         = hrs._day_end - min_sanctioned

(best_start, best_end)
end


# ============================================================
# ELVES

function scale_rating(rating, sanctioned, unsanctioned)
 max(0.25,
    min(4.0, rating * (elfs._rating_increase ^ (sanctioned/60.0)) *
            (elfs._rating_decrease ^ (unsanctioned/60.0))))
end


function create_elves(params, num_elves) 
    local elf_list = Dict()

    num_params = size(params)[1]
    rep_count = max(1,div(num_elves, num_params))
    for i in 1:num_params
        for j in 1:rep_count
            _elf = Elf((i-1)*rep_count + j, params[i,:])
            elf_list[_elf.id] = _elf
        end        
    end
    
    elf_list
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

    # XXX account for delta from best start/end.
    start_minute = max(best_start, elf_start)
    wait_time    = max(0, start_minute - elf_start)
    sanctioned, unsanctioned = get_sanctioned_breakdown(start_minute,work_duration)

    effective_prod  = ((current_toy.duration) /
                       (sanctioned + 2*unsanctioned + wait_time))
    
    new_rating      = scale_rating(current_elf.rating,
                                   sanctioned,
                                   unsanctioned)

    # What will be the new rating when done?
    scaled_rating   =  new_rating / 4
      
    # What is the effective productivity?
    scaled_prod     =  effective_prod / 4

    # How big of a job?
    scaled_jobsize  = min(1.0, current_toy.duration / (32*60))

    # Compute score based on Elf's coefficients      
    score_vec = vec([1.0, scaled_rating, scaled_prod, scaled_jobsize])
    score     = dot(current_elf.score_params, score_vec)

  float64(score)
end

function find_best_toy(current_elf, toys)
  # Score the toys and take the best one
  scores = [score_toy(t, current_elf) for t in toys] 
  first(findin(scores, maximum(scores)))
end



# ============================================================
# EVENT LOOP


type Event
    at_minute::Int
    event_type::Symbol
    id::Int
end

function Event(at_minute, event_type)
  Event(at_minute, event_type, 0)
end

function event_loop(myToys, myElves)

    num_elves = length(myElves)

    events = Collections.PriorityQueue{Event, Int}()
    for t in values(myToys)
        ev = Event(t.arrival_minute, :TOY, t.id)
        Collections.enqueue!(events, ev, ev.at_minute)
    end

    for e in values(myElves)
        ev = Event(e.next_available_time, :ELF, e.id)
        Collections.enqueue!(events, ev, ev.at_minute)        
    end
    
    wcsv = open(soln_file, "w")
    write(wcsv,"ToyId,ElfId,StartTime,Duration\n");

    local last_minute = 0
    local available_elves = Elf[]
    local available_toys  = Toy[]
    while(length(events) > 0) 

        # Get all events at next time
        current_time = Collections.peek(events)[2]
        while (length(events) > 0 &&
               (Collections.peek(events)[2] <= current_time))
            current_event = Collections.dequeue!(events)
            if (current_event.event_type == :TOY)
                push!(available_toys, myToys[current_event.id])

            elseif (current_event.event_type == :ELF)
                push!(available_elves, myElves[current_event.id])
            end
        end
               
        # XXX - enhance this to find the best allocation across all of the
        #       available toys and elfs.
        #scores = [Float64[score_toy(myToys[t], myElves[e]) for t in tmpToys] for e in available_elves]
        #M = apply(hcat, scores)        
        while ((length(available_elves) > 0) &&
               (length(available_toys)  > 0)) 

            current_elf = first(available_elves)

            # XXX - Replace with find_best_toy?
            scores = [score_toy(t, current_elf) for t in available_toys]
            best_tidx = indmax(scores)
            current_toy = available_toys[best_tidx]

            # Assign the elf
            work_start_time = current_time
            work_duration   = int(ceil(current_toy.duration / current_elf.rating))        
            update_elf(current_elf, current_toy, work_start_time, work_duration)

            # Remove toy and elf from list of available lists
            filter!(t -> t != current_toy, available_toys)
            filter!(e -> e != current_elf, available_elves)
            
            # Add event to queue
            ev = Event(current_elf.next_available_time, :ELF, current_elf.id)
            Collections.enqueue!(events, ev, ev.at_minute)
                
            # write to file in correct format
            tt = hrs._reference_start_time + Dates.Minute(work_start_time)
            time_string = join(map(string,[Dates.year(tt) Dates.month(tt) Dates.day(tt) Dates.hour(tt) Dates.minute(tt)]), " ")
            println(wcsv,current_toy.id,",",current_elf.id,",",time_string,",",work_duration)
                
            last_minute = max(last_minute, work_start_time + work_duration)
        end
    end
    close(wcsv)

    avg_prod = sum([e.rating for e in values(myElves)]) / num_elves
    
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
      "param_file"
      help = "Agent parameters file"
      required = true
end

parsed_args = parse_args(s)
NUM_ELVES   = parsed_args["nelves"]
toy_file    = parsed_args["toy_file"]
soln_file   = parsed_args["soln_file"]
params_file = parsed_args["param_file"]

# XXX - cahnge this 
#elf_coefs = vcat(repmat([(0, 1.0, 0, 0, 0)],int(NUM_ELVES/4)),
#                 repmat([(0, 0, 1.0, 0, 0)],int(NUM_ELVES/4)),
#                 repmat([(1, 0.0, 0.0, -1.0, 0)],int(NUM_ELVES/4)),                 
#                 repmat([(0, 0, 0, 1.0, 0)],int(NUM_ELVES/4)))

myToys  = read_toys(toy_file)
params  = readcsv(params_file)
myElves = create_elves(params, NUM_ELVES)

start = time()
num_elves, last_minute, avg_prod = event_loop(myToys, myElves)
elapsed_time = time() - start

score = last_minute * log(1.0 + num_elves)

@printf("Runtime= %.2f \tScore= %d \tProd=%.2f\t LastMin=%d\n",
        elapsed_time, score, avg_prod, last_minute)
        
