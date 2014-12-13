# ============================================================
# hrs.jl
#
# Julia port of the sample NaiveSolution to the
# Helping Santa's Helpers Kaggle Challenge. Original
# Python code available at:
#
# https://github.com/noahvanhoucke/HelpingSantasHelpers
#
# John Cardente, 2014
# ============================================================

module hrs

using Dates

export convert_to_minute, is_sanctioned_time, get_sanctioned_breakdown,
      next_sanctioned_minute, apply_resting_period

const _hours_per_day        = 10 # 10 hour day: 9 - 19
const _day_start            = 9 * 60
const _day_end              = (9 + _hours_per_day) * 60
const _minutes_in_24h       = 24 * 60
const _millsecs_in_minute   = 60 * 1000
const _reference_start_time = DateTime(2014, 1, 1, 0, 0, 0)

function convert_to_minute(arrival)
    local arr_time
    local dd
    local age
    # '2014 12 17 7 03'
    arr_time = map(parseint,split(arrival))
    dd   = apply(DateTime, arr_time)
    div(int(dd - _reference_start_time), _millsecs_in_minute)
end


function is_sanctioned_time(minute)
  ((minute - _day_start) % _minutes_in_24h) < (_hours_per_day * 60)
end


function get_sanctioned_breakdown(start_minute, duration)
    local full_days, sanctioned, unsanctioned, remainder_start
    
    # NB - note the integer math used to compute full_days,
    #      sanctioned and unsanctioned
    full_days       = convert(Int,floor(duration / _minutes_in_24h))
    sanctioned      = full_days * _hours_per_day * 60
    unsanctioned    = full_days * (24 - _hours_per_day) * 60
    remainder_start = start_minute + full_days * _minutes_in_24h

    # NB - Julia's colon operator includes the upper limit while
    #      Python's xrange does not. Therefore, the difference
    #      in upper limit from the sample Python code.
    for minute in colon(remainder_start, start_minute + duration - 1)
        if is_sanctioned_time(minute)
            sanctioned   += 1
        else
            unsanctioned += 1
        end
     end
   sanctioned, unsanctioned
end


function next_sanctioned_minute(minute)
    local num_days
    if is_sanctioned_time(minute) && is_sanctioned_time(minute+1)
        return minute + 1
    end

    # NB - recall that minute is relative to the _reference_start_time
    #      so _day_start is the start time on the first day
    num_days = convert(Int, floor(minute / _minutes_in_24h))
    _day_start + (num_days + 1) * _minutes_in_24h    
end 


function apply_resting_period(start, num_unsanctioned)
    local num_days_since_jan1, rest_time, rest_time_in_working_days
    local rest_time_remaining_minutes, local_start, total_days
    
    num_days_since_jan1         = div(start, _minutes_in_24h)
    rest_time                   = num_unsanctioned
    rest_time_in_working_days   = div(rest_time , (60 * _hours_per_day))
    rest_time_remaining_minutes = rest_time % (60 * _hours_per_day)

    local_start = start % _minutes_in_24h
    if local_start < _day_start
        local_start = _day_start
    elseif local_start > _day_end
        num_days_since_jan1 += 1
        local_start = _day_start
    end

    if ((local_start + rest_time_remaining_minutes) > _day_end)
        rest_time_in_working_days   += 1
        rest_time_remaining_minutes -= (_day_end - local_start)
        local_start = _day_start
    end

    total_days = num_days_since_jan1 + rest_time_in_working_days

    total_days * _minutes_in_24h + local_start + rest_time_remaining_minutes        
end

end # end module hrs
