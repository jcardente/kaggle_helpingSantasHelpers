# ============================================================
# toys.jl
#
# Julia port of the sample NaiveSolution to the
# Helping Santa's Helpers Kaggle Challenge. Original
# Python code available at:
#
# https://github.com/noahvanhoucke/HelpingSantasHelpers
#
# John Cardente, 2014
# ============================================================

module toys

using hrs

export Toy, outside_toy_start_period, is_complete

# NB - appears unused in Python sample code.
#
#using Dates
#const _default_start_time = DateTime(2014, 1, 1, 0, 0, 0)

type Toy
    id::Int
    arrival_minute::Int
    duration::Int
    completed_minute::Int
end

function Toy(id, arrival, duration)
    Toy(int(id), hrs.convert_to_minute(arrival), int(duration), 0)
end

function Toy()
    Toy(0, hrs.convert_to_minute("2014 1 1 0 0"), 0, 0)
end

function outside_toy_start_period(self, start_minute)
    start_minute < self.arrival_minute
end

function is_complete(self, start_minute, elf_duration, rating)
    if self.duration / rating <= elf_duration
        self.completed_minute = start_minute + int(ceil(self.duration / rating))
        return true
    end

    false
end

end # end module toy
