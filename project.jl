# ------------------------------------------------------------------------------
# Symbol Table and it's aux functions
#
# Notas do prof: LISTAS DE LISTAS COM OS BOUNDS!
#                DO JULIA PADRÃO SO CONSEGUIMOS USAR AS PRIMITIVAS
#
# ------------------------------------------------------------------------------

globalScope = Dict{String, Any}(); # global symbol table 

"""Creates a new environment inside the existing one"""
function newEnvironment(super_env::Dict) :: Dict
    environment = Dict{String, Any}();
    environment["#"] = super_env #FIXME: By ref?
    return environment
end

"""
Binds a symbol to a name (variable) in an environment
If the variable is already defined its value will be replaced
"""
function addVariableToEnv(var_name::String, var::Any, env::Dict)
    env[var_name]=var
end

"""Retrieves a the symbol of a variable from the environment"""
function getVariableValue(var_name::String, env::Dict) # Nullable
    # this will be a recursive function
    if(haskey(env, var_name))
        return env[var_name]
    end
    if(!haskey(env, "#")) # global scope
        return nothing
    end
    return getVariableValue(var_name, env["#"]) # scope before
end


function evaluate(ast, env::Dict=globalScope)
    # Literals
    if isa(ast, Number) || isa(ast, String)
        return ast
        # Expressions
    elseif isa(ast, Expr)
        println("[rm later] AST head type: $(ast.head)") # rm line
        println("[rm later] AST args: $(ast.args)") # rm line
        # Function calls
        if ast.head == :call
            op = ast.args[1]
            args = map(evaluate, ast.args[2:end])
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
            # Logical operators
        elseif ast.head == :(=)
            value = evaluate(ast.args[2], env)
            addVariableToEnv(string(ast.args[1]), value, env)
            return value
        elseif ast.head == :||
            return evaluate(ast.args[1]) || evaluate(ast.args[2])
        elseif ast.head == :&&                  # Logical AND
            return evaluate(ast.args[1]) && evaluate(ast.args[2])

        elseif ast.head == :if                  # If ("ternary" or "if-else-end")
            if isa(ast.args[2], Number)
                return evaluate(ast.args[1]) ? evaluate(ast.args[2]) : evaluate(ast.args[3])
            else
                return evaluate(ast.args[1]) ? evaluate(ast.args[2].args[2]) : evaluate(ast.args[3].args[2])
            end

        elseif ast.head == :block               # Block
            #TODO: This might need improvement (passing the state)
            val = nothing
            for i in ast.args
                val = evaluate(i)
            end
            return val
        elseif ast.head == :let
            #let evaluate(ast.args[1]) # let evaluate(:(x=1))
            #    return evaluate(ast.args[2]) 
            #end
        else
            error("Unsupported expression type: $(ast.head)")
        end
    else
        #! MARTELADA - Não sabemos bem o que isto é
        value = getVariableValue(string(ast), env)
        return  isnothing(value) ? error("Symbol is not defined") : value
    end
end



function printlnr(r)
    println(r)
end
function printlnr(r::String)
    println("\"$r\"")
end



function metajulia_repl()
    println("MetaJulia REPL. Type \"exit\" to quit.")
    while true

        print(">> ")
        input = readline()          # Read user input

        if input == "exit"          # Check for the exit command
            println("Exiting MetaJulia REPL.")
            break
        end

        ast = Meta.parse(input)     # Parse the input into an AST

        #println("[rm] AST head: $(ast.head)")
        #println("[rm] AST args: $(ast.args)")
        #println("[rm] type of arg 1 : $(typeof(ast.args[1]))")
        #println("[rm] head of arg 1: $(ast.args[1])")
        #println("[rm] type of arg 2 : $(typeof(ast.args[2]))")
        #println("[rm] head of arg 2: $(ast.args[2])")
        #println("[rm] arg 2 1: $(ast.args[2].args[1])")
        #println("[rm] arg 2 2: $(ast.args[2].args[2])")

        if isa(ast, Expr) || isa(ast, Number) || isa(ast, String) || isa(ast, Symbol)
            result = evaluate(ast, globalScope)
            #?                 ^ should global? ^
            printlnr(result)
        else                        # Unsupported AST types
            error("Unsupported AST node type: $(typeof(ast))")
        end
    end
end