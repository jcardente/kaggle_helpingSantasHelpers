using hrs
using toys
using elfs
using utils
#using agent
using vectorsol
using ArgParse


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
      required = false
end

parsed_args   = parse_args(s)
elf_rep_count = parsed_args["nelves"]
toy_file      = parsed_args["toy_file"]
soln_file     = parsed_args["soln_file"]
#params_file   = parsed_args["param_file"]

myToys  = read_toys(toy_file)
#params  = readcsv(params_file)
#myElves = create_elves(params, elf_rep_count)

start = time()
#solution, num_elves, last_minute, avg_prod = event_loop(myToys, myElves, soln_file)
solution, num_elves, last_minute, avg_prod = vectorSolve(myToys, elf_rep_count)
elapsed_time = time() - start

score = last_minute * log(1.0 + num_elves)

@printf("Runtime= %.2f \tScore= %d \tProd=%.2f\t LastMin=%d\n",
        elapsed_time, score, avg_prod, last_minute)
        
wcsv = open(soln_file, "w")
write(wcsv,"ToyId,ElfId,StartTime,Duration\n");
for i in 1:size(solution)[2]
    toy_id          = solution[1,i]
    elf_id          = solution[2,i]
    work_start_time = solution[3,i]
    work_duration   = solution[4,i]
    
    tt = hrs._reference_start_time + Dates.Minute(work_start_time)
    time_string = join(map(string,[Dates.year(tt) Dates.month(tt) Dates.day(tt) Dates.hour(tt) Dates.minute(tt)]), " ")
    println(wcsv,
            toy_id,",",
            elf_id,",",
            time_string,",",
            work_duration)
end

close(wcsv)
