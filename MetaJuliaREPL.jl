module MetaJuliaREPL

include("Environment.jl")
using .Environment

# -------------------------------------------------
# Data Structures
# -------------------------------------------------
struct Function
    data::String
end

struct Fexpr
    data::String
end

struct Macro
    data::String
end

function Base.show(io::IO, x::Function)
    print(io, "<function>")
end

function Base.show(io::IO, x::Fexpr)
    print(io, "<fexpr>")
end

function Base.show(io::IO, x::Macro)
    print(io, "<macro>")
end


# -------------------------------------------------
# DEBUG functions
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
# Meta-Circular Evaluator funcs
# -------------------------------------------------

# global scope
global_env = Dict{String,Any}("#" => nothing)

# This global var sets whether we are in the macro mode
# where some expressions cannot be evaluated
global isMacro = false


"""Main evaluator"""
function evaluate(node, env::Dict=global_env, singleScope::Dict=Dict{String,Any}("#" => nothing))

    if isnothing(node) # null
        return

    elseif node isa Number || node isa String # Literals
        return node

    elseif node isa Symbol # Variables
        name = string(node)
        result = getEnvBinding(env, name)

        # for the eval keyword, create an eval function
        if isnothing(result) && name == "eval"
            return createEval(env, singleScope)
        end

        return isnothing(result) ? error("Name not found: $name") : result

    elseif node isa QuoteNode # Reflection
        if node.value isa String || node.value isa Number
            return node.value
        end
        return node

    elseif node isa Expr # Expressions
        if node.head == :call  # Function calls
            return functionCallEvaluator(node, env, singleScope)

        elseif node.head == :||
            return evaluate(node.args[1], env, singleScope) || evaluate(node.args[2], env, singleScope)

        elseif node.head == :&&
            return evaluate(node.args[1], env, singleScope) && evaluate(node.args[2], env, singleScope)

        elseif node.head == :if
            return evaluate(node.args[1], env, singleScope) ? evaluate(node.args[2], env, singleScope) : evaluate(node.args[3], env, singleScope)
        elseif node.head == :elseif
            return evaluate(node.args[1].args[1], env, singleScope) ? evaluate(node.args[2], env, singleScope) : evaluate(node.args[3], env, singleScope)

        elseif node.head == :block
            value = nothing
            for arg in node.args
                value = evaluate(arg, env, singleScope)
            end
            return value # returns the last evaluated expression

        elseif node.head == :let
            inner = newEnv(env)
            evaluate(node.args[1], inner, singleScope) # assignment phase
            return evaluate(node.args[2], inner, singleScope) # block phase

        elseif node.head == :global
            return globalKeywordEvaluator(node, env, singleScope)

        elseif node.head == :-> # Anonymous functions passed as arguments
            params = node.args[1] isa Symbol ? [node.args[1]] : node.args[1].args
            block = node.args[2]
            lambda = Expr(:->, Expr(:tuple, params...), block, "func")
            return lambda

        elseif node.head == :(=)
            return assignmentEvaluator(node, env, singleScope)

        elseif node.head == :(:=)
            return fexprDefinitionEvaluator(node, env, singleScope)

        elseif node.head == :quote
            return quoteEvaluator(node, env, singleScope)

        elseif node.head == :$ # Macro variable resolver
            val = getEnvBindingSym(env, string(node.args[1]))
            return evaluate(val, env, singleScope)

        elseif node.head == :$= # Macro Definition
            return macroDefinitionEvaluator(node, env, singleScope)

        elseif node.head == :quote
            return evaluate(node.args[1], env, singleScope)

        else
            error("Unsupported expression head: $(node.head)")
        end


    else
        error("Unsupported node type: $(typeof(node))")
    end
end


"""This functions evaluates all function calls (fexpr, anon., built-in, custom, macros)"""
function functionCallEvaluator(node, env::Dict=global_env, singleScope::Dict=Dict{String,Any}("#" => nothing))
    call = node.args[1]
    global isMacro
    tempEnv = copy(env)

    isFexpr = false
    isGlobal = false

    # 
    # Fexpr eval
    # 
    if !isMacro
        if hasEnvBinding(env, string(call)) && evaluate(call, env, singleScope) isa Expr
            func = evaluate(call, env, singleScope)
            # needed to define fexpr args as quotes instead of calls
            if func.args[3] == "fexpr"
                isFexpr = true
                len = size(node.args, 1)
                for i in 2:len
                    if node.args[i] isa Expr && node.args[i].head != :quote
                        node.args[i] = Expr(:quote, node.args[i])
                    end
                end
                # needed to ensure that args are evaluated with the global function's captured env
            elseif size(func.args, 1) == 4
                isGlobal = true
                capEnv = func.args[4]
                for (key, value) in capEnv
                    if hasEnvBinding(tempEnv, key)
                        continue
                    end
                    addEnvBinding(tempEnv, key, value)
                end
            end

        end
    end

    # 
    # Parameter evaluation
    # 
    if occursin(r"macro\"\)\)$", string(getEnvBinding(env, string(node.args[1]))))
        # macro params will only be evaluated when they are called
        args = map(x -> x, node.args[2:end])
        isMacro = true
    else
        args = map(x -> evaluate(x, env, singleScope), node.args[2:end])
    end

    if call isa Symbol

        # 
        # Predefined functions
        # 
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
            sym = gensym("aaa")
            return string(sym)

            # 
            # Custom functions
            # 
        elseif hasEnvBinding(env, string(call))
            func = evaluate(call, env, singleScope)
            params = func.args[1].args
            # use captured environment if function has one

            if (isMacro)
                # macros need to be executed in the same environment
                for (param, arg) in zip(params, args)
                    addEnvBindingSym(env, string(param), arg)
                end
                val = evaluate(func.args[2], env, singleScope)
                isMacro = false
                return val
            end

            evalenv = length(func.args) >= 4 ? func.args[4] : newEnv(env)
            for (param, arg) in zip(params, args)
                addEnvBinding(evalenv, string(param), arg)
            end
            DEBUG_ENV && debug_env(evalenv)

            if isFexpr || isGlobal # if evals are called inside the function block, uses tempEnv
                return evaluate(func.args[2], evalenv, tempEnv)
            else
                return evaluate(func.args[2], evalenv, singleScope)
            end

        else
            error("Unsupported symbol call: $call")
        end

    elseif call isa Expr

        # 
        # Anonymous functions
        # 
        if call.head == :->
            temp = newEnv(env)
            params = call.args[1] isa Symbol ? [call.args[1]] : call.args[1].args
            for (param, arg) in zip(params, args)
                addEnvBinding(temp, string(param), arg)
            end
            DEBUG_ENV && debug_env(temp)
            return evaluate(call.args[2], temp, singleScope)

            # 
            # Macro-defined functions
            # 
        elseif call.head == :$
            func = getEnvBindingSym(env, string(call.args[1]))
            val = evaluate(func.args[2], env, singleScope)
            return val

        else
            error("Unsupported expression call: $call")
        end

    else
        error("Unsupported call: $call")
    end
end


"""This function evaluates assigments that use the global keyword"""
function globalKeywordEvaluator(node, env::Dict=global_env, singleScope::Dict=Dict{String,Any}("#" => nothing))
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
            return Fexpr(name)
        else # for functions
            lambda = Expr(:->, Expr(:tuple, params...), block, "func", env)
            addEnvBinding(global_env, name, lambda)
            DEBUG_ENV && debug_env(global_env)
            return Function(name)
        end

    elseif glob.args[1] isa Symbol && glob.args[2] isa Expr && glob.args[2].head == :call
        # Global function assignment to a variable (global f = id(x))
        name = string(glob.args[1])
        value = evaluate(glob.args[2], env, singleScope)
        params = value.args[1]
        block = value.args[2]
        def = value.args[3]
        lambda = Expr(:->, params, block, def, env)
        addEnvBinding(global_env, name, lambda)
        DEBUG_ENV && debug_env(global_env)
        return Function(name)

    elseif glob.args[2] isa Expr && glob.args[2].head == :->
        # Global anonymous function assignment (global f = x -> x+1)
        name = string(glob.args[1])
        params = glob.args[2].args[1] isa Symbol ? [glob.args[2].args[1]] : glob.args[2].args[1].args
        block = glob.args[2].args[2]
        # creates function (w/ captured env) on global env
        lambda = Expr(:->, Expr(:tuple, params...), block, "func", env)
        addEnvBinding(global_env, name, lambda)
        DEBUG_ENV && debug_env(global_env)
        return Function(name)

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
end


"""This function evaluates all assignments (except globals)"""
function assignmentEvaluator(node, env::Dict=global_env, singleScope::Dict=Dict{String,Any}("#" => nothing))

    # 
    # Function assignment (f(x) = ...)
    # 
    if node.args[1] isa Expr && node.args[1].head == :call
        name = string(node.args[1].args[1])

        # variables inside macros are defined with "$"
        # at the begining which is not part of the name
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
        return Function(name)

        # 
        # Anonymous function assignment with captured environment 
        # (f = let y = 1; x -> y=x+y end)
        # 
    elseif node.args[2] isa Expr && node.args[2].head == :let && node.args[2].args[2].args[1].head == :->
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
        return Function(name)

        # 
        # Anonymous function assignment without captured environment 
        # (f = x -> x+1)
        # 
    elseif node.args[2] isa Expr && node.args[2].head == :->
        name = string(node.args[1])

        if occursin(r"^\$", name)
            name = name[2:end]
        end

        params = node.args[2].args[1] isa Symbol ? [node.args[2].args[1]] : node.args[2].args[1].args
        block = node.args[2].args[2]
        lambda = Expr(:->, Expr(:tuple, params...), block, "func")
        addEnvBindingSym(env, name, lambda)
        DEBUG_ENV && debug_env(env)
        return Function(name)

        # 
        # Variable assignment (x = 1)
        # 
    elseif node.args[1] isa Symbol
        name = string(node.args[1])

        if occursin(r"^\$", name)
            name = name[2:end]
        end

        value = evaluate(node.args[2], env, singleScope)

        if size(node.args, 1) >= 2 && node.args[2] isa Expr && size(node.args[2].args, 1) >= 1 && node.args[2].args[1] == :gensym
            # special case where we need to change the env
            createGenSym(env, name, value)

            DEBUG_ENV && debug_env(env)
            return value
        end
        addEnvBindingSym(env, name, value)
        DEBUG_ENV && debug_env(env)
        return value

    else
        error("Unsupported assignment: $(node.args[1]) = $(node.args[2])")
    end
end


"""Used for reflection to avoid evaluation of calls"""
function reflect(node, env::Dict, singleScope::Dict)
    # creates a string to be evaluated by the parser
    if node isa Symbol || node isa Number
        return string(node)

    elseif node isa String
        return "\"$(string(node))\""

    elseif node.head == :($)
        # evaluates the Expr inside $() and adds it to the string
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
        return string("(", reflect(node.args[1], env, singleScope), " = ", reflect(node.args[2], env, singleScope), ")")

    else
        # if node only has one arg, then it is a function call
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


"""This function evaluates the definition of macros"""
function macroDefinitionEvaluator(node, env::Dict=global_env, singleScope::Dict=Dict{String,Any}("#" => nothing))
    name = string(node.args[1].args[1])
    params = node.args[1].args[2:end]
    body = node.args[2]

    lambda = Expr(:macro, Expr(:tuple, params...), body, "macro")

    addEnvBinding(env, name, lambda)
    DEBUG_ENV && debug_env(temp)

    return Macro(name)
end


"""This function evaluates the definition of fexpr"""
function fexprDefinitionEvaluator(node, env::Dict=global_env, singleScope::Dict=Dict{String,Any}("#" => nothing))
    name = string(node.args[1].args[1])
    params = node.args[1].args[2:end]
    block = node.args[2]
    lambda = Expr(:->, Expr(:tuple, params...), block, "fexpr")
    addEnvBinding(env, name, lambda)
    DEBUG_ENV && debug_env(env)
    return Fexpr(name)
end


"""This function evaluates quotes"""
function quoteEvaluator(node, env::Dict=global_env, singleScope::Dict=Dict{String,Any}("#" => nothing))
    if isMacro
        macroExpr = node.args[1]
        return evaluate(macroExpr, env, singleScope)
    end

    value = Meta.parse(reflect(node.args[1], env, singleScope))
    Base.remove_linenums!(value)

    return Expr(:quote, value)
end

"""This function creates an eval function"""
function createEval(env::Dict=global_env, singleScope::Dict=Dict{String,Any}("#" => nothing))
    node = Meta.parse("eval(x) = eval(x)")
    name = string(node.args[1].args[1])
    params = node.args[1].args[2:end]
    block = Base.remove_linenums!(node.args[2])
    lambda = Expr(:->, Expr(:tuple, params...), block, "func")
    addEnvBindingSym(env, name, lambda)
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


function metajulia_eval(input)

    if input isa String
        return string(input)
    end

    node = Meta.parse(string(input))
    Base.remove_linenums!(node)

    if node isa Expr || node isa Number || node isa String || node isa Symbol || node isa QuoteNode
        # Evaluate the node and print the result
        result = evaluate(node)

        #
        # Pretty-Printing for unit testing
        #
        if result isa String
            return ("\"$(result)\"")
        end

        if isnothing(result)
            result = ""
        end

        if result isa QuoteNode
            return result.value
        end

        if result isa Expr && result.head == :quote
            return result.args[1]
        end

        return result

    else
        error("Unsupported node type: $(typeof(node))")
    end
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



end # module MetaJuliaREPL

metajulia_eval(input) = Main.MetaJuliaREPL.metajulia_eval(input)

metajulia_repl() = Main.MetaJuliaREPL.metajulia_repl()

include("Test.jl")