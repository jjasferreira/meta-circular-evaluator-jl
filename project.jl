


function evaluate(ast)
    # Literals
    if isa(ast, Number) || isa(ast, String)
        return ast
        # Expressions
    elseif isa(ast, Expr)
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
        elseif ast.head == :||
            return evaluate(ast.args[1]) || evaluate(ast.args[2])
        elseif ast.head == :&&
            return evaluate(ast.args[1]) && evaluate(ast.args[2])
            # Unsupported expressions
        else
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
        # Read user input
        print(">> ")
        input = readline()
        # Check for the exit command
        if input == "exit"
            println("Exiting MetaJulia REPL.")
            break
        end
        # Parse the input into an AST
        ast = Meta.parse(input)
        # Evaluate the AST and print the result
        if isa(ast, Expr) || isa(ast, Number) || isa(ast, String) || isa(ast, Symbol)
            result = evaluate(ast)
            printlnr(result)
        # Unsupported AST types
        else
            error("Unsupported AST node type: $(typeof(ast))")
        end
    end
end


