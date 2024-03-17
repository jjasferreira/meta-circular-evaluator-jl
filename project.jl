


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
            # result = evaluate(ast)
            println(ast)
        # Unsupported AST types
        else
            error("Unsupported AST node type: $(typeof(ast))")
        end
    end
end


