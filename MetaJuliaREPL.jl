module MetaJuliaREPL

include("Environment.jl")
using .Environment

global_env = Dict{String,Any}("#" => nothing)

# -------------------------------------------------
# DEBUG
# -------------------------------------------------

DEBUG_ENV = false
DEBUG_NODE = false

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
# EVALUATE
# -------------------------------------------------

function evaluate(node, env::Dict)
    if node isa Number || node isa String # Literals
        return node

    elseif node isa Symbol # Variables
        name = string(node)
        result = getEnvBinding(env, name)
        return isnothing(result) ? error("Name not found: $name") : result

    elseif node isa QuoteNode # Reflection
        if node.value isa String || node.value isa Number
            return node.value
        end

        return node

    elseif node isa Expr # Expressions
        isMacro = false
        DEBUG_NODE && println("[DEBUG] AST is: $(node)")
        DEBUG_NODE && println("[DEBUG] AST head type: $(node.head)") # rm line
        DEBUG_NODE && println("[DEBUG] AST args: $(node.args)") # rm line
        if node.head == :call  # Function calls
            call = node.args[1]

            # needed to define fexpr args as quotes instead of calls
            if !isnothing(getEnvBinding(env, string(call))) && evaluate(call, env).args[3] == "fexpr"
                len = size(node.args, 1)
                for i in 2:len
                    if node.args[i] isa Expr
                        node.args[i] = Expr(:quote, node.args[i])
                    end
                end
            end

            if occursin(r"macro\"\)\)$", string(getEnvBinding(env, string(node.args[1]))))
                # we will need to evaluate this later
                args = map(x -> x, node.args[2:end])
                isMacro = true
            else
                args = map(x -> evaluate(x, env), node.args[2:end])
            end
            if call isa Symbol
                if call == :+
                    return sum(args)
                elseif call == :-
                    if length(args) == 1
                        return reduce(-, [0, args[1]])
                    else
                        return reduce(-, args)
                    end
                elseif call == :*
                    return prod(args)
                elseif call == :/
                    return reduce(/, args)
                elseif call == :>
                    return args[1] > args[2]
                elseif call == :<
                    return args[1] < args[2]
                elseif call == :(==)
                    return args[1] == args[2]
                elseif call == :!
                    return !evaluate(args[1], env)
                elseif call == :(eval)
                    if args[1] isa Expr && args[1].head == :quote
                        return evaluate(args[1].args[1], env)
                    else
                        return evaluate(args[1], env)
                    end
                elseif call == :(println)
                    final = string()
                    for arg in args
                        if arg isa Expr && arg.head == :quote
                            final = final * string(arg.args[1])
                        else 
                            final = final * string(arg)
                        end
                    end
                    println(final)
                    
                elseif !isnothing(getEnvBinding(env, string(call)))   # Defined functions
                    func = evaluate(call, env) # gets the function
                    if(isMacro) # its a macro
                        temp = env
                    else
                        temp = newEnv(env) 
                    end
                    # adapt to the number of function parameters (single or multiple or zero)
                    params = func.args[1] isa Symbol ? [func.args[1]] : func.args[1].args
                    for (param, arg) in zip(params, args)
                        addEnvBinding(temp, string(param), arg)
                    end
                    
                    DEBUG_ENV && println("[DEBUG] temp: $(temp)")

                    returnEval = evaluate(func.args[2], temp)
                    isMacro = false
                    return returnEval
                else
                    println(string(call))
                    println(env)
                    error("🤔")
                end

            elseif call isa Expr
                if call.head == :->     # Anonymous functions
                    temp = newEnv(env)
                    # adapt to the number of function parameters (single or multiple or zero)
                    params = call.args[1] isa Symbol ? [call.args[1]] : call.args[1].args
                    for (param, arg) in zip(params, args)
                        addEnvBinding(temp, string(param), arg)
                    end
                    DEBUG_ENV && println("[DEBUG] temp: $(temp)")
                    return evaluate(call.args[2], temp)
                elseif call.head == :macro
                    error("🤔 macro")
                else
                    error("🤔 not macro")
                end
            else
                error("Unsupported operation: $op")
            end

        elseif node.head == :||
            if evaluate(node.args[1], env)
                return evaluate(node.args[1], env)
            else 
                evaluate(node.args[2], env)
            end

        elseif node.head == :&&
            if evaluate(node.args[1], env)
                return evaluate(node.args[2], env)
            else 
                return evaluate(node.args[1], env)
            end

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
                addEnvBinding(env, name, value)
                DEBUG_ENV && println("[DEBUG] env: $(env)")
                return value
            elseif node.args[1] isa Expr && node.args[1].head == :call    # is a Function
                name = string(node.args[1].args[1])
                params = node.args[1].args[2:end]
                body = node.args[2]
                if length(params) == 1 # single function parameter
                    lambda = Expr(:->, params[1], body, "func")
                else        # multiple or zero function parameters
                    lambda = Expr(:->, Expr(:tuple, params...), body, "func")
                end
                addEnvBinding(env, name, lambda)
                DEBUG_ENV && println("[DEBUG] env: $(env)")
                return Symbol("<function>")
            end

        elseif node.head == :(:=)
            name = string(node.args[1].args[1])
            params = node.args[1].args[2:end]
            body = node.args[2]
            if length(params) == 1 # single function parameter
                lambda = Expr(:->, params[1], body, "fexpr")
            else        # multiple or zero function parameters
                lambda = Expr(:->, Expr(:tuple, params...), body, "fexpr")
            end
            addEnvBinding(env, name, lambda)
            DEBUG_ENV && println("[DEBUG] env: $(env)")
            return Symbol("<fexpr>")

        elseif node.head == :quote
            value = Meta.parse(reflect(node.args[1], env))
            Base.remove_linenums!(value)
            return Expr(:quote, value)
        
        elseif node.head == :$
            val = getEnvBinding(env, string(node.args[1]))
            return evaluate(val,env)
        
        elseif node.head == :$=          # Macro definition
            # node.args[1] = antes do $=
            # node.args[2] = depois do $=
            name = string(node.args[1].args[1])
            params = node.args[1].args[2:end]
            body = node.args[2]

            lambda = Expr(:macro, Expr(:tuple, params...), body.args..., "macro")

            addEnvBinding(env, name, lambda)
            DEBUG_ENV && println("[DEBUG] environment: $(env)")
            
            return Symbol("<macro>")

        else
            error("Unsupported expression type: $(node.head)")
        end
    elseif isnothing(node)
        return;
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
        len = size(node.args, 1)
        final = string() * "("
        for i in 2:len
            final = final * reflect(node.args[i], env)
            if i == len
                break
            end
            final = final * string(node.args[1])
        end
        final = final * ")"
        return final
    end
end

# -------------------------------------------------
# PARSER
# -------------------------------------------------

function parse_input()
    input = ""
    while input == ""
        print(">> ")
        input = readline()
    end
    node = Meta.parse(input)
    while node isa Expr && node.head == :incomplete
        print("   ")
        input *= "\n" * readline()
        node = Meta.parse(input)
    end
    Base.remove_linenums!(node)
    return node
end

function metajulia_repl()
    while true
        node = parse_input()
        DEBUG_NODE && print_node(node, "node")

        if node isa Expr || node isa Number || node isa String || node isa Symbol || node isa QuoteNode
            # Evaluate the node and print the result
            result = evaluate(node, global_env)
            result isa String ? println("\"$(result)\"") : println(result)

        else
            error("Unsupported node type: $(typeof(node))")
        end
    end
end

end # module MetaJuliaREPL

metajulia_repl() = Main.MetaJuliaREPL.metajulia_repl()