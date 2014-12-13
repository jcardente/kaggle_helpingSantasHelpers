# ============================================================
# SantasHelpers_NaiveSolution.jl
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

function create_elves(NUM_ELVES)
    local list_elves
    list_elves = Collections.PriorityQueue{Elf, Tuple}()
    for i in 1:NUM_ELVES
        _elf = Elf(i)
        Collections.enqueue!(list_elves, _elf, (_elf.next_available_time, _elf.id))
    end
    
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


function solution_firstAvailableElf(toy_file, soln_file, myelves)
    # NB- taking from hours file instead of hard coding the start
    #     date in multiple places.
    ref_time = hrs._reference_start_time
    toysfile = open(toy_file, "r")
    readline(toysfile)
    
    wcsv     = open(soln_file, "w")
    write(wcsv,"ToyId,ElfId,StartTime,Duration\n");

    while !eof(toysfile)
        row         = split(strip(readline(toysfile)),",")
        current_toy = apply(toys.Toy, row)
        
        # Get next elf
        current_elf = Collections.dequeue!(myelves)
        elf_available_time = current_elf.next_available_time

        work_start_time = elf_available_time
        if (current_toy.arrival_minute > elf_available_time)
            work_start_time = current_toy.arrival_minute
        end

        if (work_start_time < current_toy.arrival_minute)
            error(string("Work_start_time before arrival minute: ",
                         "$work_start_time $(current_toy.arrival_minute)"))
            exit(-1)
        end

        current_elf.next_available_time, work_duration = assign_elf_to_toy(work_start_time,
                                                                           current_elf,
                                                                           current_toy)
        update_elf(current_elf, current_toy, work_start_time, work_duration)
        
        # put elf back in heap
        Collections.enqueue!(myelves, current_elf, (current_elf.next_available_time, current_elf.id))

        # write to file in correct format
        tt = hrs._reference_start_time + Dates.Minute(work_start_time)
        time_string = join(map(string,[Dates.year(tt) Dates.month(tt) Dates.day(tt) Dates.hour(tt) Dates.minute(tt)]), " ")
        println(wcsv,current_toy.id,",",current_elf.id,",",time_string,",",work_duration)
    end
    
    close(toysfile)
    close(wcsv)
end


# ============================================================
# MAIN

start     = time()
NUM_ELVES = 900
toy_file  = ARGS[1]
soln_file = ARGS[2]

myelves = create_elves(NUM_ELVES)
solution_firstAvailableElf(toy_file, soln_file, myelves)

elapsed_time = time() - start
println("total runtime = $elapsed_time")
    
