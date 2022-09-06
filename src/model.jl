import MacroTools: @capture, postwalk
import DataFrames: DataFrame

export AbstractModel, @allowmissing, nullable

abstract type AbstractModel end

Base.show(io::IO, t::T) where {T<:AbstractModel} = print(io, t)
Base.print(io::IO, t::T) where {T<:AbstractModel} =  # TODO: print a vector of AMs
    let data = permutedims([string(getfield(t, name)) for name in fieldnames(T)])
        header = (collect(string.(fieldnames(T))), collect(string.(fieldtypes(T))))
        pretty_table(io, data; header)
    end
Base.print(io::IO, ts::Vector{T}) where {T<:AbstractModel} =  # TODO: print a vector of AMs
    let data = permutedims(cat([[string(getfield(t, name)) for name in fieldnames(T)] for t in ts]..., dims=2))
        header = (collect(string.(fieldnames(T))), collect(string.(fieldtypes(T))))
        pretty_table(io, data; header)
    end

Base.NamedTuple(m::T) where {T<:AbstractModel} = NamedTuple([name => getfield(m, name) for name in fieldnames(typeof(m))])  # not sure if needed
DataFrame(ts::Vector{T}) where {T<:AbstractModel} = DataFrame(NamedTuple.(ts))
DataFrame(t::T) where {T<:AbstractModel} = DataFrame([NamedTuple(t)])

"""default conversion of struct name to table name"""
tablename(::Type{T}) where {T<:AbstractModel} = T |> string |> lowercase |> Inflector.to_plural |> Symbol
"""default primary key"""
pk(::Type{T}) where {T<:AbstractModel} = T |> fieldnames |> first
"""get the primary key"""
pk(m::T) where {T<:AbstractModel} = getfield(m, pk(T))


"""Allows you to write
```jldoctest
julia> @kwdef @allowmissing struct S x::Int = missing end
julia> fieldtype(S, :x)
Union{Missing, Int64}
```"""
macro allowmissing(structdef)
    postwalk(structdef) do expr
        @capture(expr, fld_::typ_ = missing) ? :($fld::nullable($typ)) : expr
    end
end
nullable(::Type{T}) where {T} = Union{T,Missing}

generate(db::DB, genmodelname::Symbol, gentablename::Symbol) =  # maybe this can use PRIMARY KEY / FOREIGN KEY for auto pk etc.
    let res = db[From(gentablename)], gentablename = string(gentablename)
        structdef = :(struct $genmodelname <: AbstractModel end)
        fielddef(name, typ) = Missing <: typ ? :($name::$typ = missing) : :($name::$typ)
        structdef.args[3].args = map(fielddef, res.names, res.types)  # fields
        :((Base.@kwdef $structdef; FunnyORM.tablename(::Type{$genmodelname}) = Symbol($gentablename)))
    end

generate_string(db::DB, genmodelname::Symbol, gentablename::Symbol) =
    let expr = Base.remove_linenums!(FunnyORM.generate(db, genmodelname, gentablename))
        strip(replace(string(expr.args[1]) * "\n" * string(expr.args[2]), r"#=.*=#" => "", "\n    " => "\n"))
    end



precompile(generate, (DB, Symbol, Symbol))
precompile(generate_string, (DB, Symbol, Symbol))

