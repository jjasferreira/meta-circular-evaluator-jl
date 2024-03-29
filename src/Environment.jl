module Environment

export newEnv, addEnvBinding, hasEnvBinding, getEnvBinding, createGenSym, addEnvBindingSym, getEnvBindingSym



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



"""Creates a new symbolic binding in the environment"""
function createGenSym(env::Dict, originalName::String, newName::String)
    env["/"*originalName] = newName
    env[newName] = ""
end



"""Adds a binding to a name in the environment. If there is a
symbolic binding for the name, it uses the symbolic binding instead"""
function addEnvBindingSym(env::Dict, name::String, node::Any)
    if hasEnvBinding(env, "/" * name)
        name = getEnvBinding(env, "/" * name)
    end
    addEnvBinding(env, name, node)
end



"""Retrieves the node bound to a name in the environment. If there is a
symbolic binding for the name, it uses the symbolic binding instead"""
function getEnvBindingSym(env::Dict, name::String)
    if hasEnvBinding(env, "/" * name)
        addr = getEnvBinding(env, "/" * name)
        return env[addr]
    else
        return getEnvBinding(env, name)
    end
end



end # module Environment