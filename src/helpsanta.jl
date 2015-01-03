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
        help = "Elf count"
        arg_type = Int
        default = 900
    "--ntoys", "-t"
        help = "Toy Count"
        arg_type = Int
        default = 10000000
    "toy_file"
        help = "Toy input file"
        required = true
    "soln_file"
        help = "Solution output file"
        required = true
end

parsed_args = parse_args(s)
const num_elves   = parsed_args["nelves"]
const num_toys    = parsed_args["ntoys"]
const toy_file    = parsed_args["toy_file"]
const soln_file   = parsed_args["soln_file"]

start = time()
last_minute, avg_prod = vectorSolve(toy_file, soln_file, num_elves, num_toys)
elapsed_time = time() - start

score = last_minute * log(1.0 + num_elves)

@printf("Runtime= %.2f \tScore= %d \tProd=%.2f\t LastMin=%d\n",
        elapsed_time, score, avg_prod, last_minute)

