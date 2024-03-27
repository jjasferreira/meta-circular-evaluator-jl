module MetaJuliaREPL

include("Environment.jl")
using .Environment

global_env = Dict{String,Any}("#" => nothing)

# -------------------------------------------------
# DEBUG
# -------------------------------------------------

DEBUG_ENV = false
DEBUG_NODE = false

function debug_env(env::Dict{String,Any}, prefix="")
    for (key, value) in env
        if value isa Expr && value.head == :->
            params = "(" * join([string(p) for p in value.args[1].args], ", ") * ")"
            block = replace(repr(value.args[2]), "\n" => " ")
            block = replace(block, r"\s+" => " ")
            println("$prefix[ENV] $key => $params->($block)")
        elseif value isa Dict
            println("$prefix[ENV] $key => "), debug_env(value, prefix * "      ")
        else
            println("$prefix[ENV] $key => $value")
        end
    end
end

function debug_node(node, prefix="", is_last=true)
    lines = is_last ? "└── " : "├── "
    print("[NODE]$prefix$lines$(typeof(node))")
    if node isa Expr
        print("($(node.head)): ")
        args = "[" * join([string(arg) for arg in node.args], ", ") * "]"
        args = replace(args, "\n" => " ")
        println(replace(args, r"\s+" => " "))
        prefix *= (is_last ? "    " : "│   ")
        for (i, arg) in enumerate(node.args)
            debug_node(arg, prefix, i == length(node.args))
        end
    else
        println(": $node")
    end
end

# -------------------------------------------------
# EVALUATE
# -------------------------------------------------
global isMacro = false
function evaluate(node, env::Dict=global_env, singleScope::Dict=Dict{String,Any}("#" => nothing))

    if isnothing(node) # null value
        return

    elseif node isa Number || node isa String # Literals
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
        #isMacro = false
        #println("[DEBUG] AST is: $(node)") #rm
        #println("[DEBUG] AST head type: $(node.head)") #rm
        #println("[DEBUG] AST args: $(node.args)") #rm
        #println("[DEBUG] ", env) #rm
        if node.head == :call  # Function calls
            call = node.args[1]
            global isMacro
            tempEnv = copy(env)

            # needed to define fexpr args as quotes instead of calls
            isFexpr = false
            if !isMacro
                if !isnothing(getEnvBinding(env, string(call))) && evaluate(call, env, singleScope).args[3] == "fexpr"
                    len = size(node.args, 1)
                    for i in 2:len
                        if node.args[i] isa Expr && node.args[i].head != :quote
                            println("fexpr arg before ", node.args[i])
                            node.args[i] = Expr(:quote, node.args[i])
                            println("fexpr arg after ", node.args[i])
                        end
                    end
                end
            end

            if occursin(r"macro\"\)\)$", string(getEnvBinding(env, string(node.args[1]))))
                # we will need to evaluate this later
                args = map(x -> x, node.args[2:end])
                isMacro = true
            else
                args = map(x -> evaluate(x, env, singleScope), node.args[2:end])
            end

            if call isa Symbol # || isMacro
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
                elseif call == :^
                    return reduce(^, args)
                elseif call == :/
                    return reduce(/, args)
                elseif call == :%
                    return reduce(%, args)
                elseif call == :<
                    return args[1] < args[2]
                elseif call == :<=
                    return args[1] <= args[2]
                elseif call == :(==)
                    return args[1] == args[2]
                elseif call == :>=
                    return args[1] >= args[2]
                elseif call == :>
                    return args[1] > args[2]
                elseif call == :(!=)
                    return args[1] != args[2]
                elseif call == :!
                    return !args[1]

                elseif call == :(eval)
                    if args[1] isa Expr && args[1].head == :quote
                        return evaluate(args[1].args[1], singleScope)
                    else
                        return evaluate(args[1], singleScope)
                    end
                elseif call == :(println)
                    final = string()
                    for arg in args
                        if arg isa Expr && arg.head == :quote
                            final = final * string(arg.args[1])
                        elseif arg isa Expr && arg.head == :->
                            final = final * string("<function>")
                        else
                            final = final * string(arg)
                        end
                    end
                    println(final)
                elseif call == :(gensym)
                    # println("GENSYM")
                    # for i in args
                    #     println("Arg: ", i)
                    # end
                    sym = gensym("aaa")
                    #println("type: ", typeof(sym))
                    #println("value: ", sym)
                    return string(sym)
                elseif hasEnvBinding(env, string(call)) # Defined functions
                    """
                    if (isMacro)
                        temp = env
                    else
                        temp = newEnv(env)
                    end
                    """
                    #println(">>>> ",call)
                    #println(env)
                    func = evaluate(call, env)
                    params = func.args[1].args
                    # use captured environment if function has one

                    if(isMacro)
                        #println("MACROOOOOO")
                        for (param, arg) in zip(params, args)
                            addEnvBindingSym(env, string(param), arg)
                        end
                        #println(env)
                        #println("vou avaliar isto: ", string(func.args[2]))
                        #println("vou avaliar isto: ", string(func.args[2])[3:(end-1)])
                        #aa = Meta.parse(string(func.args[2]))
                        #Base.remove_linenums!(aa)
                        val = evaluate(func.args[2], env)
                        isMacro = false
                        return val
                    end

                    evalenv = length(func.args) >= 4 ? func.args[4] : newEnv(env)
                    for (param, arg) in zip(params, args)
                        addEnvBinding(evalenv, string(param), arg)
                    end
                    DEBUG_ENV && debug_env(evalenv)

                    if isFexpr
                        return evaluate(func.args[2], evalenv, tempEnv)
                    else
                        return evaluate(func.args[2], evalenv, singleScope)
                    end
                    """
                    returnEval = evaluate(func.args[2], temp, singleScope)
                    isMacro = false
                    return returnEval
                    """
                else
                    error("Unsupported symbol call: $call")
                end

            elseif call isa Expr
                if call.head == :->     # Anonymous functions
                    #println("lontrinha")
                    temp = newEnv(env)
                    params = call.args[1] isa Symbol ? [call.args[1]] : call.args[1].args
                    for (param, arg) in zip(params, args)
                        addEnvBinding(temp, string(param), arg)
                    end
                    DEBUG_ENV && debug_env(temp)
                    return evaluate(call.args[2], temp, singleScope)
                elseif call.head == :macro
                    error("🤔 macro")
                elseif call.head == :$
                    #println("ccccccccc")
                    #println("\$"*string(call))
                    #println(call.args)
                    #TODO Invocation
                    #println(env)
                    

                    leFunction = getEnvBindingSym(env, string(call.args[1]))
                    #for (param, arg) in zip(params, args)
                    #    addEnvBinding(env, string(param), arg)
                    #end
                    #println(env)
                    #println("LE FUNCTION, ", leFunction)
                    val = evaluate(leFunction.args[2], env)
                    return val
                else
                    error("Unsupported expression call: $call")
                end
            else
                error("Unsupported call: $call")
            end

        elseif node.head == :||
            return evaluate(node.args[1], env, singleScope) || evaluate(node.args[2], env, singleScope)
            """ TODO if not working, try this:
            if evaluate(node.args[1], env, singleScope)
                return evaluate(node.args[1], env, singleScope)
            else
                evaluate(node.args[2], env, singleScope)
            end
            """
        elseif node.head == :&&
            return evaluate(node.args[1], env, singleScope) && evaluate(node.args[2], env, singleScope)
            """ TODO if not working, try this:
            if evaluate(node.args[1], env, singleScope)
                return evaluate(node.args[2], env, singleScope)
            else
                return evaluate(node.args[1], env, singleScope)
            end
            """

        elseif node.head == :if
            return evaluate(node.args[1], env, singleScope) ? evaluate(node.args[2], env, singleScope) : evaluate(node.args[3], env, singleScope)

        elseif node.head == :block
            value = nothing
            for arg in node.args
                value = evaluate(arg, env, singleScope)
            end
            return value

        elseif node.head == :let
            inner = newEnv(env)
            evaluate(node.args[1], inner, singleScope) # assignment phase
            return evaluate(node.args[2], inner, singleScope) # block phase

        elseif node.head == :global
            glob = node.args[1]
            if glob.args[1] isa Expr && glob.args[1].head == :call
                # Global function assignment (global f(x) = x+1)
                name = string(glob.args[1].args[1])
                params = glob.args[1].args[2:end]
                block = glob.args[2]
                # creates function (w/ captured env) on global env
                if glob.head == :(:=) # for fexprs
                    lambda = Expr(:->, Expr(:tuple, params...), block, "fexpr", env)
                    addEnvBinding(global_env, name, lambda)
                    DEBUG_ENV && debug_env(global_env)
                    return Symbol("<fexpr>")
                else # for functions
                    lambda = Expr(:->, Expr(:tuple, params...), block, "func", env)
                    addEnvBinding(global_env, name, lambda)
                    DEBUG_ENV && debug_env(global_env)
                    return Symbol("<function>")
                end
            elseif glob.args[2] isa Expr && glob.args[2].head == :->
                # Global anonymous function assignment (global f = x -> x+1)
                name = string(glob.args[1])
                params = glob.args[2].args[1] isa Symbol ? [glob.args[2].args[1]] : glob.args[2].args[1].args
                block = glob.args[2].args[2]
                # creates function (w/ captured env) on global env
                lambda = Expr(:->, Expr(:tuple, params...), block, "func", env)
                addEnvBinding(global_env, name, lambda)
                DEBUG_ENV && debug_env(global_env)
                return Symbol("<function>")
            elseif glob.args[1] isa Symbol
                # Global variable assignment (global x = 1)
                name = string(glob.args[1])
                value = evaluate(glob.args[2], env, singleScope)
                addEnvBinding(global_env, name, value)
                DEBUG_ENV && debug_env(global_env)
                return value
            else
                error("Unsupported global assignment: $(glob.args[1]) = $(glob.args[2])")
            end

        elseif node.head == :-> # Anonymous functions passed as arguments
            
            params = node.args[1] isa Symbol ? [node.args[1]] : node.args[1].args
            block = node.args[2]
            lambda = Expr(:->, Expr(:tuple, params...), block, "func")
            return lambda

        elseif node.head == :(=)
            
            if node.args[1] isa Expr && node.args[1].head == :call
                # Function assignment (f(x) = ...)
                name = string(node.args[1].args[1])

                if occursin(r"^\$", name)
                    name = name[2:end]
                end

                params = node.args[1].args[2:end]
                block = node.args[2]
                if block.args[1] isa Expr && block.args[1].head == :let
                    # with captured environment (f(x) = let y = 1; x+y end)
                    capt = newEnv(env)
                    evaluate(block.args[1].args[1], capt, singleScope) # assignments only
                    lambda = Expr(:->, Expr(:tuple, params...), block.args[1].args[2], "func", capt)
                else
                    # without captured environment (f(x) = x+1)
                    lambda = Expr(:->, Expr(:tuple, params...), block, "func")
                end
                addEnvBindingSym(env, name, lambda)
                DEBUG_ENV && debug_env(env)
                return Symbol("<function>")
            elseif node.args[2] isa Expr && node.args[2].head == :let && node.args[2].args[2].args[1].head == :->
                # Anonymous function assignment with captured environment (f = let y = 1; x -> y=x+y end)
                name = string(node.args[1])

                if occursin(r"^\$", name)
                    name = name[2:end]
                end

                params = node.args[2].args[2].args[1].args[1] isa Symbol ? [node.args[2].args[2].args[1].args[1]] : node.args[2].args[2].args[1].args
                block = node.args[2].args[2].args[1].args[2]
                capt = newEnv(env)
                evaluate(node.args[2].args[1], capt, singleScope) # assignments only
                lambda = Expr(:->, Expr(:tuple, params...), block, "func", capt)
                addEnvBindingSym(env, name, lambda)
                DEBUG_ENV && debug_env(env)
                return Symbol("<function>")
            elseif node.args[2] isa Expr && node.args[2].head == :->
                # Anonymous function assignment without captured environment (f = x -> x+1)
                name = string(node.args[1])

                if occursin(r"^\$", name)
                    name = name[2:end]
                end

                params = node.args[2].args[1] isa Symbol ? [node.args[2].args[1]] : node.args[2].args[1].args
                block = node.args[2].args[2]
                lambda = Expr(:->, Expr(:tuple, params...), block, "func")
                addEnvBindingSym(env, name, lambda)
                DEBUG_ENV && debug_env(env)
                return Symbol("<function>")
            elseif node.args[1] isa Symbol
                # Variable assignment (x = 1)
                name = string(node.args[1])

                if occursin(r"^\$", name)
                    name = name[2:end]
                end

                value = evaluate(node.args[2], env, singleScope)
                #println("pppp ", size(node.args,1))
                #println("qqqq ", typeof(node.args[2]))
                if size(node.args,1) >= 2 && node.args[2] isa Expr && size(node.args[2].args,1) >= 1 && node.args[2].args[1] == :gensym
                    # special case where we need to change the env
                    #println("lontrinha")
                    createGenSym(env, name, value)
                    #addEnvBinding(env, "/"*name, value) # add variable generated by gensym
                    #addEnvBinding(env, value, "") # add variable generated by gensym
                    DEBUG_ENV && debug_env(env)
                    return value
                end
                addEnvBindingSym(env, name, value)
                DEBUG_ENV && debug_env(env)
                return value
            else
                error("Unsupported assignment: $(node.args[1]) = $(node.args[2])")
            end

        elseif node.head == :(:=)
            name = string(node.args[1].args[1])
            params = node.args[1].args[2:end]
            block = node.args[2]
            lambda = Expr(:->, Expr(:tuple, params...), block, "fexpr")
            addEnvBinding(env, name, lambda)
            DEBUG_ENV && debug_env(env)
            return Symbol("<fexpr>")

        elseif node.head == :quote
            #println("OOOOOOOO")
            if(isMacro)
                #println("WEEEEEEEEEE")
                aaa = node.args[1]
                return evaluate(aaa, env)
            end
            #println("UUUUUU")
            value = Meta.parse(reflect(node.args[1], env, singleScope))
            Base.remove_linenums!(value)
            return Expr(:quote, value)

        elseif node.head == :$
            val = getEnvBindingSym(env, string(node.args[1]))
            if isnothing(val)
                # try again with dolar sign
                # TODO: DO better in this
                val = getEnvBinding(env, getEnvBinding(env, string(node.args[1])))
                #println("\$"*string(node.args[1]))
                #println(env)
            end 
            return evaluate(val, env, singleScope)

        elseif node.head == :$=          # Macro definition
            # node.args[1] = antes do $=
            # node.args[2] = depois do $=
            name = string(node.args[1].args[1])
            params = node.args[1].args[2:end]
            body = node.args[2]

            #ast2 = Meta.parse(body)
            #println("PARSER, ", ast2.head)
            #println("PARSER, ", ast2.args)


            teste = []
            push!(teste, body.head)
            for i in body.args
                #println("ARG: ", i.args)
                push!(teste, i)
            end
            
            #println(teste)





            #println(Expr(:macro, Expr(:tuple, params...), :($(teste...),), "macro"))
            #println(Expr(:macro, Expr(:tuple, params...), body.args..., "macro"))


            lambda = Expr(:macro, Expr(:tuple, params...), body, "macro")

            addEnvBinding(env, name, lambda)
            DEBUG_ENV && debug_env(temp)

            return Symbol("<macro>")
        
        elseif node.head == :quote
            #println("WTF", node.args)
            return evaluate(node.args[1])
        else
            error("Unsupported expression head: $(node.head)")
        end
    elseif isnothing(node)
        return
    else
        error("Unsupported node type: $(typeof(node))")
    end
end


function reflect(node, env::Dict, singleScope::Dict) # Used for reflection to avoid evaluation of calls
    if node isa Symbol || node isa Number
        return string(node)
    elseif node isa String
        return "\"$(string(node))\""
    elseif node.head == :($)
        return string(evaluate(node.args[1], env, singleScope))
    elseif node isa Expr && node.head == :block
        final = string() * "("
        len = size(node.args, 1)
        for i in 1:len
            final = final * reflect(node.args[i], env, singleScope)
            if i == len
                break
            end
            final = final * ";"
        end
        final = final * ")"
        return final
    elseif node isa Expr && node.head == :(=)
        return string("(", reflect(node.args[1], env, singleScope), " = ",  reflect(node.args[2], env, singleScope), ")")
        
    else
        len = size(node.args, 1)
        final = string() * "("
        if len == 2
            final = final * string(node.args[1]) * "(" * reflect(node.args[2], env, singleScope) * ")"
        else
            for i in 2:len
                final = final * reflect(node.args[i], env, singleScope)
                if i == len
                    break
                end
                final = final * string(node.args[1])
            end
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
        DEBUG_NODE && debug_node(node)

        if node isa Expr || node isa Number || node isa String || node isa Symbol || node isa QuoteNode

            # Evaluate the node and print the result
            result = evaluate(node)

            # no printing for null values
            if isnothing(result)
                continue
            end

            result isa String ? println("\"$(result)\"") : println(result)

        else
            error("Unsupported node type: $(typeof(node))")
        end
    end
end

#metajulia_repl()

end # module MetaJuliaREPL

metajulia_repl() = Main.MetaJuliaREPL.metajulia_repl()