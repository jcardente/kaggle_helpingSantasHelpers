
module vectorsol

using hrs
using elfs
using toys
using Dates
using Devectorize

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
        min      = arrival % (hrs._minutes_in_24h)
        
        myToys[:,id] = [id; arrival; duration; day; min]
        
        sanctioned, unsanctioned = get_sanctioned_breakdown(hrs._day_start,
                                                            duration)

        optRatios[id] =  unsanctioned/sanctioned
    end
    close(toysfile)

    nothing
end

function adj_arrival(idx, myToys)
    local retval = myToys[2,idx]
    if (myToys[5,idx] < hrs._day_start)
        retval = (myToys[4,idx]-1) * hrs._minutes_in_24h + hrs._day_start
    elseif (myToys[5,idx] >= hrs._day_end)
        retval = (myToys[4,idx]) * hrs._minutes_in_24h + hrs._day_start
    end
    retval
end

function vectorSolve(toy_file, soln_file, num_elves, num_toys)
    
    # Create data structures to hold toys
    @printf(STDERR,"Reading toys......")
    myToys    = zeros(Int64, 5, num_toys)
    optRatios = zeros(Float64, num_toys)
    #toy_order = zeros(Int64, num_toys)
    read_fast!(toy_file, myToys, optRatios)
    @printf(STDERR,"Done\n")

    @printf(STDERR,"Sorting toys....")
    sort_arrivals = map(x -> adj_arrival(x,myToys), [1:num_toys])
    const toy_order  = sortperm([1:num_toys], lt= (a,b) -> (sort_arrivals[a] <= sort_arrivals[b]) & (myToys[3,a] > myToys[3,b]))
    local toy_done = falses(num_toys)
    const days    = myToys[4,toy_order]'
    const max_day::Int64  = maximum(days)
    @printf(STDERR,"Done\n")
    
    # Setup elf matrices
    next_minutes = ones(Int64, num_elves)  .* hrs._day_start
    ratings      = ones(Float64,num_elves) .* elfs._start_rating
    assign_count = zeros(Int64, num_elves)
    elf_day_max  = (hrs._hours_per_day +2) * 60
    assignments  = zeros(Int64, 4, elf_day_max, num_elves)
    done_mask    = falses(num_elves) #fill(Inf, num_elves)
    
    # Prep output file
    wcsv = open(soln_file, "w")
    write(wcsv,"ToyId,ElfId,StartTime,Duration\n");
    
    # Cycle through end of days or until    
    #
    # NB - Pre-allocate and type everything for speed
    #
    @printf(STDERR,"Starting solution\n")
    const elf_range         = Int64[1:num_elves]
    const toy_range         = Int64[1:num_toys]
    const elf_assign_range  = Int64[1:elf_day_max]
    local work_times        = zeros(Int64, num_elves)
    local current_day::Int64 = 0
    local day_idx::Int64     = 1    
    local min_av_toy::Int64 = 1
    local max_av_toy::Int64 = 1
    local last_minute::Int64       = 0
    local done_count::Int64        = 0
    local daily_work::Int64        = 0
    local time_string::String       = ""
    local day_start_minute::Int64  = 0
    local day_end_minute::Int64    = 0
    local elf_done::Int64          = 0
    local mt::Int64         = 0
    local idx::Int64        = 0
    local i::Int64          = 0
    local j::Int64          = 0
    local oidx::Int64              = 0
    local tid::Int64   = 0
    local this_duration::Int64     = 0
    local this_start_minute::Int64 = 0
    local this_sanctioned::Int64   = 0
    local this_unsanctioned::Int64 =    0
    local arrival::Int64 = 0
    local duration::Int64 = 0
    local hrs_ratio::Float64 = 0
    local toy_id::Int64
    local elf_id::Int64
    local work_start_time::Int64
    local work_duration::Int64
    local tt::DateTime    
    while (done_count < num_toys)

        current_day     += 1
        day_start_minute = (current_day - 1) * hrs._minutes_in_24h
        day_end_minute   = day_start_minute + hrs._day_end
        
        while ((day_idx <= length(days)) &&
               (days[day_idx] <= current_day))
            day_idx += 1;
        end        
        max_av_toy = min(day_idx-1, length(days))
        
        # Check to see if an elf is working on a multi-day toy
        elf_done = 0
        for eid in elf_range
            if (next_minutes[eid] >= day_end_minute)
                @inbounds done_mask[eid] = true                
                elf_done += 1
            else
                @inbounds done_mask[eid] = false
            end
        end

        for oidx = min_av_toy:max_av_toy

            @inbounds tid = toy_order[oidx]                
            if toy_done[oidx]
                continue
            end
            
            if elf_done >= num_elves 
                break
            end
                               
            arrival   = myToys[2,tid] 
            duration  = myToys[3,tid]
            hrs_ratio = optRatios[tid]

            # Calculate some metrics and select Elf with minimum
            # score.
            start_times = max(arrival, next_minutes, day_start_minute + hrs._day_start)
            @simd for eidx = 1:num_elves 
                @inbounds work_times[eidx] = int(ceil(duration / ratings[eidx]))
            end
            end_times   = start_times .+ work_times


            mt  = typemax(Int32)
            idx = 0
            for eid in elf_range
                if (done_mask[eid])
                    continue
                end
                if (end_times[eid] < mt)
                    mt = end_times[eid]
                    idx = eid
                end
            end
            

            # See if this is an optimal time to start this toy
            this_duration     = work_times[idx]
            this_start_minute = start_times[idx] 
            this_sanctioned, this_unsanctioned =
                get_sanctioned_breakdown(this_start_minute,  this_duration)

            this_ratio = this_unsanctioned/ this_sanctioned
            if ((this_unsanctioned > 10) && (this_ratio > hrs_ratio))
                # This assignment doesn't achieve the optimal ratio
                # of sanctioned and unsanctioned hours. Reschedule
                continue
            end

            # Looks good, assign toy to elf
            assign_count[idx] += 1
            assignments[1,assign_count[idx],idx] = tid
            assignments[2,assign_count[idx],idx] = idx
            assignments[3,assign_count[idx],idx] = this_start_minute
            assignments[4,assign_count[idx],idx] = this_duration

            @inbounds toy_done[oidx] = true
            done_count    += 1
            daily_work    += this_duration

            if (oidx == min_av_toy)
                while((min_av_toy < max_av_toy) &&( toy_done[min_av_toy]))
                    min_av_toy += 1
                end
            end
            
            
            # Calculate end time
            this_work_end_time = this_start_minute + this_duration 
            last_minute        = max(last_minute, this_work_end_time)
            
            # Update elf
            if (this_unsanctioned > 0)             
                this_next_minute = apply_resting_period(this_work_end_time, this_unsanctioned)       
            else
                if (hrs.is_sanctioned_time(this_work_end_time))
                    this_next_minute = this_work_end_time
                else
                    this_next_minute = hrs.next_sanctioned_minute(this_work_end_time)
                end
            end           

            if (this_next_minute >= (day_start_minute + hrs._day_end))
                done_mask[idx] = true
                elf_done +=1
            end
            
            next_minutes[idx] = this_next_minute
            ratings[idx]      = adjust_rating(ratings[idx],
                                              this_sanctioned,
                                              this_unsanctioned)
        end

        # Record and reset assignments
        for i=elf_range, j=elf_assign_range
            if (j > assign_count[i])
                continue
            end 
            @inbounds toy_id          = assignments[1,j,i]
            @inbounds elf_id          = assignments[2,j,i] 
            @inbounds work_start_time = assignments[3,j,i] 
            @inbounds work_duration   = assignments[4,j,i]
            
            tt = hrs._reference_start_time + Dates.Minute(work_start_time)
            time_string = @sprintf("%d %d %d %d %d",
                                   Dates.year(tt),
                                   Dates.month(tt),
                                   Dates.day(tt),
                                   Dates.hour(tt),
                                   Dates.minute(tt))

            println(wcsv,
                    toy_id,",",
                    elf_id,",",
                    time_string,",",
                    work_duration)                
        end

        ## Clear out the assignments matrix
        fill!(assignments,0)
        fill!(assign_count, 0)


        ## Print some stats
        @printf(STDERR, "D:%4d  C:%8d  R:%1.2f  U:%1.2f\n",
                current_day, done_count, mean(ratings),
                daily_work / (num_elves * hrs._hours_per_day * 60))
        daily_work = 0
       
    end
    close(wcsv)
        
    avg_prod = mean(ratings)
    return last_minute, avg_prod    
end

end # end module

