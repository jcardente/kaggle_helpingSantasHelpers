module utils

export read_toys, create_elves

using hrs
using toys
using elfs


## function read_toys(toy_file)
##     toysfile = open(toy_file, "r")
##     readline(toysfile)

##     toy_list = Dict()
##     while !eof(toysfile)
##         row = split(strip(readline(toysfile)),",")
##         new_toy = Toy(row[1], row[2], row[3])
##         toy_list[new_toy.id] = new_toy 
##     end
      
##     toy_list
## end


function read_toys(toy_file)
    toysfile = open(toy_file, "r")
    readline(toysfile)

    toy_list = Toy[];
    while !eof(toysfile)
        row = split(strip(readline(toysfile)),",")
        new_toy = Toy(row[1], row[2], row[3])
        push!(toy_list, new_toy)
    end
      
    toy_list
end


function create_elves(params, rep_count) 
    local elf_list = Dict()

    num_params = size(params)[1]
    for i in 1:num_params
        for j in 1:rep_count
            _elf = Elf((i-1)*rep_count + j, params[i,:])
            elf_list[_elf.id] = _elf
        end        
    end
    
    elf_list
end


end
