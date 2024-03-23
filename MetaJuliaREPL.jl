module MetaJuliaREPL

include("Environment.jl")
using .Environment

global_env = Dict{String,Any}("#" => nothing)


# -------------------------------------------------
# DEBUG
# -------------------------------------------------

DEBUG_ENV = true
DEBUG_NODE = true

function print_node(node, prefix="")
    println("[DEBUG] $prefix type: $(typeof(node))")
    if node isa Expr
        println("[DEBUG] $prefix head: $(node.head)")
        println("[DEBUG] $prefix args: $(node.args)")
        for (i, arg) in enumerate(node.args)
            print_node(arg, "$prefix arg$i ")
        end
    else
        println("[DEBUG] $prefix value: $node")
    end
end


# -------------------------------------------------
# AST and Parser
# -------------------------------------------------

function evaluate(node, env::Dict)

    if node isa Number || node isa String # Literals
        return node

    elseif node isa Symbol # Variables
        name = string(node)
        result = getEnvBinding(env, name)
        return isnothing(result) ? error("Name not found: $name") : result

    elseif node isa QuoteNode # Reflection
        return node

    elseif node isa Expr # Expressions
        if node.head == :call  # Function calls
            call = node.args[1]
            args = map(x -> evaluate(x, env), node.args[2:end])
            if call isa Symbol
                if call == :+
                    return sum(args)
                elseif call == :-
                    return reduce(-, args)
                elseif call == :*
                    return prod(args)
                elseif call == :/
                    return reduce(/, args)
                elseif call == :>
                    return args[1] > args[2]
                elseif call == :<
                    return args[1] < args[2]
                elseif haskey(env, string(call))  # Defined functions
                    func = evaluate(call, env)
                    temp = newEnv(env)
                    # adapt to the number of function parameters (single or multiple or zero)
                    params = func.args[1] isa Symbol ? [func.args[1]] : func.args[1].args
                    for (param, arg) in zip(params, args)
                        addBindingToEnv(temp, string(param), arg)
                    end
                    return evaluate(func.args[2], temp)
                end
            elseif call isa Expr
                if call.head == :->     # Anonymous functions
                    temp = newEnv(env)
                    # adapt to the number of function parameters (single or multiple or zero)
                    params = call.args[1] isa Symbol ? [call.args[1]] : call.args[1].args
                    for (param, arg) in zip(params, args)
                        addBindingToEnv(temp, string(param), arg)
                    end
                    return evaluate(call.args[2], temp)
                end

            else
                error("Unsupported operation: $op")
            end
        elseif node.head == :||
            return evaluate(node.args[1], env) || evaluate(node.args[2], env)
        elseif node.head == :&&
            return evaluate(node.args[1], env) && evaluate(node.args[2], env)

        elseif node.head == :if
            return evaluate(node.args[1], env) ? evaluate(node.args[2], env) : evaluate(node.args[3], env)

        elseif node.head == :block
            value = nothing
            for arg in node.args
                value = evaluate(arg, env)
            end
            return value

        elseif node.head == :let
            inner = newEnv(env)
            evaluate(node.args[1], inner) # assignment phase
            return evaluate(node.args[2], inner) # block phase

        elseif node.head == :(=)
            if node.args[1] isa Symbol    # is a Variable
                name = string(node.args[1])
                value = evaluate(node.args[2], env)
                addBindingToEnv(env, name, value)
                DEBUG_ENV && println("[DEBUG] environment: $(env)")
                return value
            elseif node.args[1] isa Expr && node.args[1].head == :call    # is a Function
                name = string(node.args[1].args[1])
                params = node.args[1].args[2:end]
                body = node.args[2]
                if length(params) == 1 # single function parameter
                    lambda = Expr(:->, params[1], body)
                else        # multiple or zero function parameters
                    lambda = Expr(:->, Expr(:tuple, params...), body)
                end
                addBindingToEnv(env, name, lambda)
                DEBUG_ENV && println("[DEBUG] environment: $(env)")
                return Symbol("<function>")
            end

        elseif node.head == :quote
            value = Meta.parse(reflect(node.args[1], env))
            return Expr(:quote, value)

        else
            error("Unsupported expression type: $(node.head)")
        end
    else
        error("Unsupported node type: $(typeof(node))")
    end
end


function reflect(node, env::Dict) # Used for reflection to avoid evaluation of calls
    if node isa Symbol || node isa Number || node isa String
        return string(node)
    elseif node.head == :($)
        return string(evaluate(node.args[1], env))
    elseif node isa Expr
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
        # Parse the input into an Abstract Syntax Tree node and remove line numbers
        node = Meta.parse(input)
        Base.remove_linenums!(node)
        if !(node isa String) && !(node isa Number) && !(node isa Symbol) 
            while node.head == :incomplete
                new_input = readline()
                input = input * "\n" * new_input
                node = Meta.parse(input)
            end
        end

        DEBUG_NODE && print_node(node, "node")

        if node isa Expr || node isa Number || node isa String || node isa Symbol || node isa QuoteNode
            # Evaluate the AST and print the result
            result = evaluate(node, global_env)
            result isa String ? println("\"$(result)\"") : println(result)

        else # Unsupported AST node types
            error("Unsupported AST node type: $(typeof(node))")
        end
    end
end

end # module MetaJuliaREPL

metajulia_repl() = Main.MetaJuliaREPL.metajulia_repl()