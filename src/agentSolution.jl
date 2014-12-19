
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

function adjust_rating(rating, sanctioned, unsanctioned)
 max(0.25,
    min(4.0, rating * (elfs._rating_increase ^ (sanctioned/60.0)) *
            (elfs._rating_decrease ^ (unsanctioned/60.0))))
end


function create_elves(params, rep_count) 
    local elf_list = Dict()

    num_params = size(params)[1]
    for i in 1:num_params
        for j in 1:rep_count
            _elf = Elf((i-1)*rep_count + j, params[i,:])
            elf_list[_elf.id] = _elf
        end        
    end
    
    elf_list
end



# ============================================================
# SCORING

function score_toy(current_toy, current_elf) 
    elf_start     = current_elf.next_available_time % hrs._minutes_in_24h
    work_duration = int(ceil(current_toy.duration / current_elf.rating))

    # XXX - convert to a lookup table to speed computations
    best_start, best_end = best_start_window(work_duration)

    # XXX account for delta from best start/end.
    sanctioned, unsanctioned = get_sanctioned_breakdown(elf_start,work_duration)

    effective_prod  = ((current_toy.duration) /
                       (sanctioned + 2*unsanctioned))
    
    new_rating      = adjust_rating(current_elf.rating,
                                   sanctioned,
                                   unsanctioned)
        
    # What will be the new rating when done?
    scaled_rating   =  new_rating / 4
      
    # What is the effective productivity?
    scaled_prod     =  effective_prod / 4

    # How fast can we get this done?
    scaled_speed    = (current_toy.duration/work_duration) / 4
    
    # How big of a job? Consider 32 hours and more the "max"
    # big job size.
    scaled_jobsize  = min(1.0, current_toy.duration / (32*60))

    # Compute score based on Elf's coefficients      
    score_vec = vec([1.0, scaled_rating, scaled_prod, scaled_jobsize, scaled_speed])
    score     = dot(current_elf.score_params, score_vec)

  float64(score)
end

function score_toys(myToys, available_toys, current_elf)
    # NB - orginally implemented as list comprehension but
    #      the syntax confused Emacs Julia mode indentation
    #      so going with a function. Can replace with macro later.
    scores = Dict()
    for tid in available_toys
        current_toy = myToys[tid]
        score =  score_toy(current_toy, current_elf)
        if (score >= current_elf.score_thresh)
            scores[tid] = score
        end        
    end

    scores
end


function score_elves(myElves, available_elves, current_toy)
    # NB - orginally implemented as list comprehension but
    #      the syntax confused Emacs Julia mode indentation
    #      so going with a function. Can replace with macro later.
    scores = Dict()
    for eid in available_elves
        current_elf = myElves[eid]
        score = score_toy(current_toy, current_elf)
        if (score >= current_elf.score_thresh)
            scores[eid] = score
        end        
    end

    scores
end


function find_max_score(score_dict)
    local score_max = -1
    local score_idx =  0

    for (k,v) in score_dict
        if (v > score_max)
            score_max = v
            score_idx = k
        end
    end

    return score_idx, score_max
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


function assign_fancy(myElves, myToys, available_elves, available_toys)
    tids = [t for t in available_toys]
    eids = [e for e in available_elves]

    scores = zeros(length(eids), length(tids))
    for tidx in 1:length(tids)
        for eidx in 1:length(eids)
            scores[eidx, tidx] = score_toy(myToys[tids[tidx]],
                                           myElves[eids[eidx]])
        end
    end
        
    assignments = Tuple[]
    while (maximum(scores) > 0)
        maxidx = findmax(scores)[2]
        indxs = ind2sub(size(scores), maxidx)
        scores[indxs[1],: ] = 0
        scores[:,indxs[2]]  = 0

        pair = (eids[indxs[1]], tids[indxs[2]])
        push!(assignments, pair)
    end

    assignments
end


function assign_simple(myElves, myToys, available_elves, available_toys)

    assignments = Tuple[]
    av_elves = copy(available_elves)
    av_toys  = copy(available_toys)
    while ((length(av_elves) > 0) &&
        (length(av_toys)  > 0)) 

        if (true)
            current_elf = myElves[first(av_elves)]
            scores      = score_toys(myToys, av_toys, current_elf)
            best_tidx   = find_max_score(scores)[1]
            current_toy = myToys[best_tidx]
                
        else
            current_toy = myToys[first(av_toys)]
            scores      = score_elves(myElves, av_elves, current_toy)
            best_eidx   = find_max_score(scores)[1]
            current_elf = myElves[best_eidx]
        end

        setdiff!(av_toys,  current_toy.id)
        setdiff!(av_elves, current_elf.id)

        pair = (current_elf.id, current_toy.id)
        push!(assignments, pair)        
    end

    assignments
end



function event_loop(myToys, myElves)

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
    local available_elves = IntSet()
    local available_toys  = IntSet()
    while(length(events) > 0) 

        # Get all events at next time
        current_time = Collections.peek(events)[2]
        while (length(events) > 0 &&
               (Collections.peek(events)[2] <= current_time))
            current_event = Collections.dequeue!(events)
            if (current_event.event_type == :TOY)
                union!(available_toys, current_event.id)

            elseif (current_event.event_type == :ELF)
                union!(available_elves, current_event.id)
            end
        end

        if ((length(available_elves) == 0) ||
            (length(available_toys) == 0))
            continue
        end
        
        
        # Assign toys and elves 
        assignments = assign_fancy(myElves, myToys,
                                    available_elves, available_toys)          

        # Process the assignments
        for pair in assignments           
            current_elf = myElves[pair[1]]
            current_toy = myToys[pair[2]]

            setdiff!(available_toys,  current_toy.id)
            setdiff!(available_elves, current_elf.id)
            
            work_start_time = current_time
            work_duration   = int(ceil(current_toy.duration / current_elf.rating))
            work_end_time   = work_start_time + work_duration
            
            sanctioned, unsanctioned = get_sanctioned_breakdown(work_start_time,
                                                                work_duration)
            local next_available_time

            if unsanctioned == 0
                # NB No rest period required. Elf is available to work anytime
                # unless the end_time is at exactly 19:00, then the elf
                # has to wait until the next sanctioned minute
                if ((work_end_time  % hrs._minutes_in_24h) == (19 * 60))
                    next_available_time = next_sanctioned_minute(work_end_time)
                else
                    next_available_time = work_end_time
                end    
            else
                next_available_time = apply_resting_period(work_end_time,
                                                             unsanctioned)
            end
                                   
            current_elf.next_available_time = next_available_time
            current_elf.rating = adjust_rating(current_elf.rating, sanctioned, unsanctioned)
 
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

    num_elves = length(myElves)
    avg_prod = sum([e.rating for e in values(myElves)]) / num_elves
    
    return num_elves, last_minute, avg_prod
end



# ============================================================
# MAIN

if (!isinteractive())        
s = ArgParseSettings()
@add_arg_table s begin
    "--nelves", "-e"
        help = "Elf prototype multiplier"
        arg_type = Int
        default = 1
    "toy_file"
        help = "Toy input file"
        required = true
    "soln_file"
        help = "Solution output file"
    required = true
      "param_file"
      help = "Elf prototype params file"
      required = true
end

parsed_args   = parse_args(s)
elf_rep_count = parsed_args["nelves"]
toy_file      = parsed_args["toy_file"]
soln_file     = parsed_args["soln_file"]
params_file   = parsed_args["param_file"]

myToys  = read_toys(toy_file)
params  = readcsv(params_file)
myElves = create_elves(params, elf_rep_count)

start = time()
num_elves, last_minute, avg_prod = event_loop(myToys, myElves)
elapsed_time = time() - start

score = last_minute * log(1.0 + num_elves)

@printf("Runtime= %.2f \tScore= %d \tProd=%.2f\t LastMin=%d\n",
        elapsed_time, score, avg_prod, last_minute)
        
end
