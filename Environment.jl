# ------------------------------------------------------------------------------
# Notas do prof: LISTAS DE LISTAS COM OS BOUNDS!
#                DO JULIA PADRÃO SO CONSEGUIMOS USAR AS PRIMITIVAS
# ------------------------------------------------------------------------------

module Environment
export newEnv, addEnvBinding, hasEnvBinding, getEnvBinding



"""Creates a new environment inside the one passed as argument"""
function newEnv(outer::Dict{String,Any})
    return Dict{String,Any}("#" => outer)
end



"""Adds or replaces a binding to a name in the environment"""
function addEnvBinding(env::Dict, name::String, node::Any)
    env[name] = node
end


"""Checks if a name is bound in the environment"""
function hasEnvBinding(env::Dict, name::String)
    if haskey(env, name)
        return true
    elseif isnothing(env["#"])
        return false
    end
    return hasEnvBinding(env["#"], name)
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