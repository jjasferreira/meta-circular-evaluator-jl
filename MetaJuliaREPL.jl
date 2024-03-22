module MetaJuliaREPL
export metajulia_repl

include("Environment.jl")
using .Environment

global_env = Dict{String,Any}("#" => nothing)



function evaluate(node, env::Dict=global_env)

    if isa(node, Number) || isa(node, String) # Literals
        return node

    elseif isa(node, Symbol) # Variables
        name = string(node)
        result = getEnvBinding(env, name)
        return isnothing(result) ? error("Name not found: $name") : result

    elseif isa(node, Expr) # Expressions
        if node.head == :call  # Function calls
            op = node.args[1]
            args = map(evaluate, node.args[2:end])
            if op == :+
                return sum(args)
            elseif op == :-
                return reduce(-, args)
            elseif op == :*
                return prod(args)
            elseif op == :/
                return reduce(/, args)
            elseif op == :>
                return args[1] > args[2]
            elseif op == :<
                return args[1] < args[2]
            else
                error("Unsupported operation: $op")
            end
        elseif node.head == :||
            return evaluate(node.args[1]) || evaluate(node.args[2])
        elseif node.head == :&&
            return evaluate(node.args[1]) && evaluate(node.args[2])

        elseif node.head == :if
            return evaluate(node.args[1]) ? evaluate(node.args[2]) : evaluate(node.args[3])

        elseif node.head == :block
            #TODO: This might need improvement (passing the state)
            val = nothing
            for arg in node.args
                if typeof(arg) != LineNumberNode
                    val = evaluate(arg)
                end
            end
            return val

        elseif node.head == :let
            val = nothing
            for arg in node.args
                if typeof(arg) != LineNumberNode
                    val = evaluate(arg)
                end
            end
            return val

        elseif node.head == :(=)
            name = string(node.args[1])
            addBindingToEnv(env, name, node.args[2])
            return evaluate(node.args[2])

        else
            error("Unsupported expression type: $(node.head)")
        end
    end
end



function metajulia_repl()
    println("MetaJulia REPL. Type \"exit\" to quit.")
    while true

        print(">> ")
        input = readline()
        if input == "exit"
            println("Exiting MetaJulia REPL.")
            break
        end
        # Parse the input into an Abstract Syntax Tree node
        node = Meta.parse(input)

        # TODO remove this later
        debug(node, "node")

        if isa(node, Expr) || isa(node, Number) || isa(node, String) || isa(node, Symbol)
            # Evaluate the AST and print the result
            result = evaluate(node)
            isa(result, String) ? println("\"$r\"") : println(result)

        else # Unsupported AST node types
            error("Unsupported AST node type: $(typeof(ast))")
        end
    end
end



# TODO remove this later
function debug(node, prefix="")
    println("$prefix type: $(typeof(node))")
    if isa(node, Expr)
        println("$prefix head: $(node.head)")
        println("$prefix args: $(node.args)")
        for (i, arg) in enumerate(node.args)
            debug(arg, "$prefix arg$i ")
        end
    else
        println("$prefix value: $node")
    end
end



end # module MetaJuliaREPL