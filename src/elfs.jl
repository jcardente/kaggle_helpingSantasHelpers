# ============================================================
# elfs.jl
#
# Julia port of the sample NaiveSolution to the
# Helping Santa's Helpers Kaggle Challenge. Original
# Python code available at:
#
# https://github.com/noahvanhoucke/HelpingSantasHelpers
#
# John Cardente, 2014
# ============================================================

module elfs

using hrs
using toys

const _start_rating    = 1.0
const _start_time      = hrs._day_start
const _rating_increase = 1.02
const _rating_decrease = 0.90

export Elf, update_elf, update_next_available_minute, update_productivity

type Elf
    id::Int
    score_params::Array{Float64,1}
    score_thresh::FloatingPoint
    rating::FloatingPoint
    next_available_time::Int    
end

function Elf(id)
    Elf(id, [0.0; 1.0; 1.0; 1.0], 0.0, _start_rating, _start_time)
end

## function Elf(id, coef_intercept, coef_rating, coef_prod, coef_jobsize, coef_thresh)
##     Elf(id, [coef_intercept; coef_rating; coef_prod; coef_jobsize],
##         coef_thresh, _start_rating, _start_time)
## end

# XXX - fix this so that it doesn't need to be changed when
#       a new scoring parameter is added
function Elf(id, params)
    Elf(id, vec(params[1:5]), params[6], _start_rating, _start_time)
end


function update_elf(self, current_toy, start_minute, duration)
    update_next_available_minute(self, start_minute, duration)
    update_productivity(self, start_minute,
                        int(ceil(current_toy.duration / self.rating)))    
end


function update_next_available_minute(self, start_minute, duration)
    local end_minute
    local sanctioned
    local unsanctioned

    sanctioned, unsanctioned = hrs.get_sanctioned_breakdown(start_minute, duration)

    end_minute = start_minute + duration
    if unsanctioned == 0
        # NB - note that an elf ending work before 19:00 can start work
        #      during unstanctioned hours but an elf ending at exactly
        #      19:00 must wait until the next day.
        #
        # See forum thread: TBD
        if (hrs.is_sanctioned_time(end_minute))
            self.next_available_time = end_minute
        else
            self.next_available_time = hrs.next_sanctioned_minute(end_minute)
        end        
    else
        self.next_available_time = hrs.apply_resting_period(end_minute, unsanctioned)
    end
end


function update_productivity(self, start_minute, toy_required_minutes)
    sanctioned, unsanctioned = hrs.get_sanctioned_breakdown(start_minute, toy_required_minutes)
    self.rating = max(0.25,
                      min(4.0, self.rating * (_rating_increase ^ (sanctioned/60.0)) *
                          (_rating_decrease ^ (unsanctioned/60.0))))
end

end # end module elf
