
module vectorsol

using hrs
using elfs
using toys

export vectorSolve

function tlt (a,b) 
    (a[2] <= b[2]) & (a[3] > b[3])
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
    ratings      = fill(elfs._start_rating, num_elves);    
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

        print(".")
        
        # Add new toys and resort
        if (current_day <= max_day)
            append!(av_toys, toys_day[current_day])
        end
        sort!(av_toys, lt=tlt)            	

                   
        # iterate over toys until all plans full or
        # no more available toys
        leftover_toys = Tuple[]
        done_mask     = map(x -> (x < hrs._day_end) ? 1.0 : Inf, next_minutes)
        while ((length(av_toys) > 0) &&
               (any(done_mask .< Inf)))
    
            tup      = shift!(av_toys)
            tid      = tup[1]            
            arrival  = tup[2]
            duration = tup[3]
            
            wait_times = max(0, arrival .- next_minutes)     
            work_times = duration ./ ratings
            rem_times  = 1140 - (next_minutes + wait_times + work_times)
            #left_times = map( x -> (x > 0) ? x : 0, rem_times)
            #unsanctioned_times = map( x -> (x < 0) ? abs(x) : 0, rem_times)

            # XXX - figure out a better score metric?
            # XXX - Add work_times
            (mt, idx) = findmin(done_mask .*
                                (abs(rem_times) .+ wait_times))
            
            this_start_minute = next_minutes[idx] + wait_times[idx]
            this_duration     = work_times[idx]
            this_next_minute  = this_start_minute + this_duration            
            this_unsanctioned = max(0, this_next_minute - hrs._day_end)
            this_sanctioned   = this_duration - this_unsanctioned
            
            ## if (this_unsanctioned > 30)
            ##     # Too much unsanctioned time
            ##     # XXX - need a way to determine if this is a super
            ##     #       big toy and let the allocation happen
            ##     push!(leftover_toys, tup)
            ##     continue
            ## end
            
            push!(assignments[idx], (tid, idx, this_start_minute, this_duration))
            # XXX - update rating
            next_minutes[idx] = this_next_minute           
            if ( this_unsanctioned > 0)
                done_mask[idx] = Inf
            end
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
        
        # reset next_minutes
        last_minute = max(last_minute, maximum(next_minutes))
        next_minutes = max(0, next_minutes .- hrs._day_end) .+
                       fill(hrs._day_start, num_elves);
        
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

