module MetaJuliaREPL

include("Environment.jl")
using .Environment

global_env = Dict{String,Any}("#" => nothing)


# -------------------------------------------------
# DEBUG
# -------------------------------------------------

DEBUG_ENV = false
DEBUG_NODE = true

function print_node(node, prefix="")
    println("[DEBUG] $prefix type: $(typeof(node))")
    if isa(node, Expr)
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

    if isa(node, Number) || isa(node, String) # Literals
        return node

    elseif isa(node, QuoteNode) # Reflection
        return node

    elseif isa(node, Symbol) # Variables
        name = string(node)
        result = getEnvBinding(env, name)
        return isnothing(result) ? error("Name not found: $name") : result

    elseif isa(node, Expr) # Expressions
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

                # x(5)       [x, 5]
            elseif haskey(env, string(op))  # Defined functions
                # env = ("x" => ("args" => ["y"], "body" => quote y + 1 end))
                func = env[string(op)]
                # func = ("args" => ["y"], "body" => quote y + 1 end)
                func_args = func["args"]
                func_body = func["body"]
                # execute the func_body with func_args substituted with args
                inner = newEnv(env)
                for (i, arg) in enumerate(func_args)
                    addBindingToEnv(inner, arg, args[i]) #inner: ("y" => 5)
                end
                return evaluate(func_body, inner)

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
            val = nothing
            for arg in node.args
                val = evaluate(arg, env)
            end
            return val

        elseif node.head == :let
            inner = newEnv(env)
            evaluate(node.args[1], inner) # assignment phase
            return evaluate(node.args[2], inner) # block phase

        elseif node.head == :(=)
            if isa(node.args[1], Symbol)    # is a Variable
                name = string(node.args[1])
                value = evaluate(node.args[2], env)
                addBindingToEnv(env, name, value)
                DEBUG_ENV && println("[DEBUG] environment: $(env)")
                return value
            elseif isa(node.args[1], Expr) && node.args[1].head == :call    # is a Function
                name = string(node.args[1].args[1])
                func = Dict{String,Any}()
                func["args"] = []
                for arg in node.args[1].args[2:end]
                    push!(func["args"], string(arg))
                end
                func["body"] = node.args[2]
                addBindingToEnv(env, name, func)
                DEBUG_ENV && println("[DEBUG] environment: $(env)")
                return "<function>"
            end

        elseif node.head == :quote
            value = Meta.parse(reflect(node.args[1], env))
            return Expr(:quote, value)

        else
            error("Unsupported expression type: $(node.head)")
        end
    else
        #! MARTELADA - Não sabemos bem o que isto é
        #TODO: Maybe precisamos de um if para garantir que é uma var
        value = getEnvBinding(string(node), env)
        return isnothing(value) ? error("Symbol is not defined") : value
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
        # Parse the input into an Abstract Syntax Tree node and remove line numbers
        node = Meta.parse(input)
        Base.remove_linenums!(node)

        DEBUG_NODE && print_node(node, "node")

        if isa(node, Expr) || isa(node, Number) || isa(node, String) || isa(node, Symbol) || isa(node, QuoteNode)
            # Evaluate the AST and print the result
            result = evaluate(node, global_env)
            isa(result, String) ? println("\"$(result)\"") : println(result)

        else # Unsupported AST node types
            error("Unsupported AST node type: $(typeof(node))")
        end
    end
end

end # module MetaJuliaREPL

metajulia_repl() = Main.MetaJuliaREPL.metajulia_repl()