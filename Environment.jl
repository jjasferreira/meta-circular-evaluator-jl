# ------------------------------------------------------------------------------
# Notas do prof: LISTAS DE LISTAS COM OS BOUNDS!
#                DO JULIA PADRÃO SO CONSEGUIMOS USAR AS PRIMITIVAS
# ------------------------------------------------------------------------------

module Environment
export newEnv, addBindingToEnv, getEnvBinding



"""Creates a new environment inside the one passed as argument"""
function newEnv(outer::Dict{String,Any})
    return Dict{String,Any}("#" => outer)
end



"""Adds or replaces a binding to a name in the environment"""
function addBindingToEnv(env::Dict, name::String, node::Any)
    env[name] = node
end



"""Retrieves the node bound to a name in the environment"""
function getEnvBinding(env::Dict, name::String)
    if haskey(env, name)
        return env[name]
    elseif isnothing(env["#"])
        return nothing
    end
    return getEnvBinding(env["#"], name)
end



end # module Environment