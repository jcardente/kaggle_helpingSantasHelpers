
module vectorsol

using hrs
using elfs
using toys

export vectorSolve

function tlt (a,b) 
    (a[2] <= b[2]) & (a[3] > b[3])
end


function adjust_rating(rating, sanctioned, unsanctioned)
 max(0.25,
    min(4.0, rating * (elfs._rating_increase ^ (sanctioned/60.0)) *
            (elfs._rating_decrease ^ (unsanctioned/60.0))))
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

function vectorSolve(myToys, num_elves)
    
    # bucket toys into days
    days    = div([t.arrival_minute for t in myToys], (24*60)) .+ 1;
    max_day = maximum(days)   
    toys_day = Array(Any, max_day)
    for d in 1:max_day
        toys_day[d] = Tuple[]
        for tid in findin(days, d)
            t = myToys[tid]
            push!(toys_day[d], (t.id, t.arrival_minute, t.duration))
        end
    end

    # Setup elf vectors
    next_minutes = fill(hrs._day_start, num_elves);
    ratings      = ones(num_elves) .* elfs._start_rating;    
    work_hours   = zeros(num_elves)
    assignments  = Array(Any, num_elves)
    for i in 1:num_elves
        assignments[i] = Tuple[]
    end

    # Array to hold solution
    solution = Array(Int32, 4, length(myToys))
    soln_idx = 1    

    # Cycle through end of days or until 
    current_day = 0
    av_toys     = Tuple[]
    jobs        = Any[]
    last_minute = 0
    while (((current_day += 1) <= max_day) ||
           (length(av_toys) > 0))
        
        day_start_minute = (current_day - 1) * hrs._minutes_in_24h
        
        # Add new toys and resort
        if (current_day <= max_day)
            append!(av_toys, toys_day[current_day])
        end
        sort!(av_toys, lt=tlt)           	
                   
        # iterate over toys until all plans full or
        # no more available toys
        leftover_toys = Tuple[]
        done_mask     = map(x -> x < (day_start_minute + hrs._day_end) ? 1.0 : Inf, next_minutes)
        while ((length(av_toys) > 0) &&
               (any(done_mask .< Inf)))
    
            tup      = shift!(av_toys)
            tid      = tup[1]            
            arrival  = tup[2] 
            duration = tup[3]

            # Calculate some metrics and select Elf with minimum
            # score.
            start_times = max(arrival, next_minutes)
            work_times  = int(ceil(duration ./ ratings))
            wait_times  = max(0, arrival .- next_minutes)
            rem_times   = max(0,(start_times .+ work_times ) - hrs._day_end)

            #1140 - (next_minutes + wait_times + work_times)

            ## XXX - use the optimal ratio for the decision to postpone
            ##       a toy's allocation. Use the estimated worktime and remtime
            ##       as filtering criteria, make remtime cost 2x worktime for
            ##       the minimum.
            
            ## THESE SIGNALS DID PRETTY WELL
            ##
            ## work_times = int(ceil(duration ./ ratings))
            ## rem_times  = 1140 - (next_minutes + wait_times + work_times)
            ## 
            ## # XXX - figure out a better score metric?
            ## # XXX - Add work_times
            ## (mt, idx) = findmin(done_mask .*
            ##                     (abs(rem_times) .+ wait_times))

            
            # Score metrics, scaled 0-1
            # start_time  .% hrs._minutes_in_24h) .- hrs._day_start) ./ (hrs._hours_per_day * 60)            
            #wait_times  = max(0, arrival .- next_minutes) ./ duration
            #rem_times   = 1- max(1,duration ./ ((hrs._day_end * 60) .- next_minutes))
            #speeds      = 1- ratings ./ 4
            #jobsize     = fill(min(1.0, duration / (32*60)), num_elves)
            
            (mt, idx) = findmin(done_mask .*
                                ((2*rem_times) .+ work_times .+ wait_times))

            # See if this is an optimal time to start this toy
            this_duration     = work_times[idx]
            this_start_minute = next_minutes[idx] + wait_times[idx]            
            this_sanctioned, this_unsanctioned =
                get_sanctioned_breakdown(this_start_minute,  this_duration)
 
            ## best_start, best_end = best_start_window(this_duration)           
            ## this_rel_start = (this_start_minute % hrs._minutes_in_24h)
            ## best_delta     = min(max(0,this_rel_start - best_start),
            ##                      abs(this_rel_start - best_end))
            if ((this_sanctioned/ this_unsanctioned) < 5.3)
                ## @printf("T:%d D:%d S:%d NS:%d BS:%d BE:%d\n",
                ##         tid, duration, this_start_minute,
                ##         (this_start_minute % hrs._minutes_in_24h), best_start, best_end)
                ## push!(leftover_toys, tup)
                continue
            end

            # Looks good, do the assignment
            push!(assignments[idx],
                  (tid, idx, this_start_minute, this_duration))
            
            
            # Calculate end time
            this_work_end_time = this_start_minute + this_duration 
            last_minute        = max(last_minute, this_work_end_time)
            
            # Update elf
            if (this_unsanctioned > 0)             
                this_next_minute = apply_resting_period(this_work_end_time, this_unsanctioned)       
                done_mask[idx]   = Inf
            else
                if (hrs.is_sanctioned_time(this_work_end_time))
                    this_next_minute = this_work_end_time
                else
                    this_next_minute = hrs.next_sanctioned_minute(this_work_end_time)
                end
            end           
            
            next_minutes[idx] = this_next_minute
            ratings[idx]      = adjust_rating(ratings[idx],
                                              this_sanctioned,
                                              this_unsanctioned)
        end


        # Record and reset assignments
        for i in 1:num_elves
            if (length(assignments[i]) > 0)
                append!(jobs, assignments[i])
                assignments[i] = Tuple[]
            end
        end
                
        # Carry over any left over toys
       append!(av_toys, leftover_toys)
                                    
    end

    for j in jobs
        solution[1,soln_idx] = j[1]
        solution[2,soln_idx] = j[2]
        solution[3,soln_idx] = j[3]
        solution[4,soln_idx] = j[4]
        soln_idx += 1           
    end

    avg_prod = mean(ratings)
    return solution, num_elves, last_minute, avg_prod    
end

end # end module

