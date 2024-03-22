module MetaJuliaREPL
export metajulia_repl

include("Environment.jl")
using .Environment

global_env = Dict{String,Any}("#" => nothing)


# -------------------------------------------------
# DEBUG
# -------------------------------------------------

debug = true # Debug messages for environment
# change it to false if you want to disable it

# TODO remove this later
function print_aditional_debug_info(node, prefix="")
    println("$prefix type: $(typeof(node))")
    if isa(node, Expr)
        println("$prefix head: $(node.head)")
        println("$prefix args: $(node.args)")
        for (i, arg) in enumerate(node.args)
            print_aditional_debug_info(arg, "$prefix arg$i ")
        end
    else
        println("$prefix value: $node")
    end
end


# -------------------------------------------------
# AST and Parser
# -------------------------------------------------

function evaluate(node, env::Dict)
    debug && println("[DEBUG] ENV: $(env)")

    if isa(node, Number) || isa(node, String) # Literals
        return node

    elseif isa(node, QuoteNode) # Reflection
        return node

    elseif isa(node, Symbol) # Variables
        name = string(node)
        result = getEnvBinding(env, name)
        return isnothing(result) ? error("Name not found: $name") : result

    elseif isa(node, Expr) # Expressions
        Base.remove_linenums!(node)
        debug && println("[DEBUG] AST head type: $(node.head)") # rm line
        debug && println("[DEBUG] AST args: $(node.args)") # rm line
        if node.head == :call  # Function calls
            op = node.args[1]
            args = map(x -> evaluate(x, env), node.args[2:end])
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
            return evaluate(node.args[1],env) || evaluate(node.args[2],env)
        elseif node.head == :&&
            return evaluate(node.args[1],env) && evaluate(node.args[2],env)

        elseif node.head == :if
            return evaluate(node.args[1],env) ? evaluate(node.args[2],env) : evaluate(node.args[3],env)

        elseif node.head == :block
            # julia seems to be defining the block in the current scope
            # so no need to create a new env
            val = nothing
            for arg in node.args
                val = evaluate(arg,env)
            end
            return val

        elseif node.head == :let
            localScope = newEnv(env)
            evaluate(node.args[1], localScope) # assignment phase
            return evaluate(node.args[2],localScope) # block phase

        elseif node.head == :(=)
            name = string(node.args[1])
            value = evaluate(node.args[2], env)
            addBindingToEnv(env, name, value)
            return value

        elseif node.head == :quote
            value = Meta.parse(reflect(node.args[1], env))
            return Expr(:quote, value)

        else
            error("Unsupported expression type: $(node.head)")
        end
    else
        #! MARTELADA - Não sabemos bem o que isto é
        #TODO: Maybe precisamos de um if para garantir que é uma var
        debug && println("[DEBUG] Variable to check: $(node)")
        debug && println("[DEBUG] ENV: $(env))")
        value = getVariableValue(string(node), env)
        return  isnothing(value) ? error("Symbol is not defined") : value
    end
end


function reflect(node, env::Dict) # Used for reflection to avoid evaluation of calls
    if isa(node, Symbol) || isa(node, Number) || isa(node, String)
        return string(node)
    elseif node.head == :($)
        return string(evaluate(node.args[1], env))
    elseif isa(node, Expr)
        return "(" * reflect(node.args[2], env) * string(node.args[1]) * reflect(node.args[3], env) * ")"
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
        print_aditional_debug_info(node, "node")

        if isa(node, Expr) || isa(node, Number) || isa(node, String) || isa(node, Symbol) || isa(node, QuoteNode)
            # Evaluate the AST and print the result
            result = evaluate(node,global_env)
            isa(result, String) ? println("\"$(result)\"") : println(result)

        else # Unsupported AST node types
            error("Unsupported AST node type: $(typeof(node))")
        end
    end
end

end # module MetaJuliaREPL