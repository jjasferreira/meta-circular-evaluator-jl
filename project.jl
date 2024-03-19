


function evaluate(ast)
    if isa(ast, Number) || isa(ast, String) # Literals
        return ast
    elseif isa(ast, Expr)                   # Expressions
        if ast.head == :call                    # Function calls
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

        elseif ast.head == :||                  # Logical OR    
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

        else                                # Unsupported expressions
            error("Unsupported expression type: $(ast.head)")
        end
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
            result = evaluate(ast)  # Evaluate the AST and print the result
            printlnr(result)
        else                        # Unsupported AST types
            error("Unsupported AST node type: $(typeof(ast))")
        end
    end
end