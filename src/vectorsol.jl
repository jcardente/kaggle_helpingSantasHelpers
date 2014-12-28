
module vectorsol

using hrs
using elfs
using toys
using Dates

export vectorSolve, read_fast, adjust_rating


function adjust_rating(rating, sanctioned, unsanctioned)
 max(0.25,
    min(4.0, rating * (elfs._rating_increase ^ (sanctioned/60.0)) *
            (elfs._rating_decrease ^ (unsanctioned/60.0))))
end


function read_fast!(toy_file, myToys, optRatios)
    toysfile = open(toy_file, "r")
    readline(toysfile)
    while !eof(toysfile)
        row = split(strip(readline(toysfile)),",") # id, arrival_minute, duration
        id       = int(row[1])
        arrival  = convert_to_minute(row[2])
        duration = int(row[3])
        day      = div(arrival, hrs._minutes_in_24h) + 1

        myToys[:,id] = [id; arrival; duration; day]
        
        sanctioned, unsanctioned = get_sanctioned_breakdown(hrs._day_start,
                                                            duration)

        optRatios[id] =  unsanctioned/sanctioned
    end
    close(toysfile)

    nothing
end


function vectorSolve(toy_file, soln_file, num_elves, num_toys)
    
    # Create data structures to hold toys
    myToys    = zeros(Int64, 4, num_toys)
    optRatios = zeros(Float64, num_toys)
    toy_done  = falses(num_toys)
    read_fast!(toy_file, myToys, optRatios)
    days      = myToys[4,:]'
    max_day   = maximum(days)
    
    # Setup elf matrices
    next_minutes = ones(Int64, num_elves)  .* hrs._day_start
    ratings      = ones(Float64,num_elves) .* elfs._start_rating
    assign_count = zeros(Int64, num_elves)
    assignments  = zeros(Int64, 4, hrs._hours_per_day * 60, num_elves)

    # Prep output file
    wcsv = open(soln_file, "w")
    write(wcsv,"ToyId,ElfId,StartTime,Duration\n");
    
    # Cycle through end of days or until
    current_day    = 0
    day_idx        = 1    
    min_av_toy     = 1
    max_av_toy     = 1
    last_minute    = 0
    assigned_count = 0
    while (!all(toy_done))

        current_day += 1
        day_start_minute = (current_day - 1) * hrs._minutes_in_24h
        
        println("Day: $(current_day) Done:$(assigned_count) $(sum(toy_done)) of $(length(toy_done)) $(min_av_toy) $(max_av_toy)")
                
        # Add new toys and resort.
        #
        # NB - this relies on the fact that the toys
        #      are ordered by time and assiged sequential
        #      ids. 
        if (current_day <= max_day)
            # NB - possible no toys arrive on a day
            if ((day_idx < length(days)) &&
                (days[day_idx] == current_day))
                while ((day_idx <= length(days)) &&
                    (days[day_idx] == current_day))
                    day_idx += 1;
                end;
                max_av_toy = max(max_av_toy, myToys[1,day_idx-1])
            end
        end

        # iterate over toys until all plans full or
        # no more available toys
        done_mask = map(x -> x < (day_start_minute + hrs._day_end) ? 1.0 : Inf, next_minutes)
        for tid in sort([min_av_toy:max_av_toy], by= x -> myToys[3,x], rev=true)           	

            if (toy_done[tid])
                continue
            end
            
            if (!any(done_mask .< Inf))
                break
            end
                               
            arrival   = myToys[2,tid] 
            duration  = myToys[3,tid]
            hrs_ratio = optRatios[tid]

            # Calculate some metrics and select Elf with minimum
            # score.
            start_times = max(arrival, next_minutes, day_start_minute)
            work_times  = int(ceil(duration ./ ratings))
            wait_times  = max(0, arrival .- next_minutes)
            rem_times   = max(0,(start_times .+ work_times ) - hrs._day_end)

            (mt, idx) = findmin(done_mask .*
                                ((2*rem_times) .+ work_times .+ wait_times))

            # See if this is an optimal time to start this toy
            this_duration     = work_times[idx]
            this_start_minute = start_times[idx] 
            this_sanctioned, this_unsanctioned =
                get_sanctioned_breakdown(this_start_minute,  this_duration)

            this_ratio = this_unsanctioned/ this_sanctioned
            if ((this_unsanctioned > 10) && (this_ratio > hrs_ratio))
                # This assignment doesn't achieve the optimal ratio
                # of sanctioned and unsanctioned hours. Reschedule
                #println("$(tid) $(this_ratio) $(hrs_ratio) $(this_start_minute) $(this_duration) $(this_sanctioned) $(this_unsanctioned)")
                continue
            end

            # Looks good, do the assignment
            assign_count[idx] += 1
            assignments[:,assign_count[idx],idx] = [tid; idx; this_start_minute; this_duration]
            toy_done[tid] = true
            min_av_toy    = min(min_av_toy, tid)
            
            assigned_count += 1
            if ((assigned_count % 10000) == 0)
                @printf("Assigned toys: %d\n", assigned_count)
            end
            
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
            for j in 1:assign_count[i]
                toy_id          = assignments[1,j,i]
                elf_id          = assignments[2,j,i] 
                work_start_time = assignments[3,j,i] 
                work_duration   = assignments[4,j,i]
    
                tt = hrs._reference_start_time + Dates.Minute(work_start_time)
                time_string = join(map(string,[Dates.year(tt) Dates.month(tt) Dates.day(tt) Dates.hour(tt) Dates.minute(tt)]), " ")
                println(wcsv,
                        toy_id,",",
                        elf_id,",",
                        time_string,",",
                        work_duration)
                
            end
        end

        ## Clear out the assignments matrix
        fill!(assignments,0)
        fill!(assign_count, 0)

    end
    close(wcsv)
        
    avg_prod = mean(ratings)
    return last_minute, avg_prod    
end

end # end module

