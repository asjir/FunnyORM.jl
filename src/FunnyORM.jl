module FunnyORM

import FunSQL: FunSQL, Agg, Append, As, Asc, Bind, Define, Desc, Fun, From, Get,
    Group, Highlight, Iterate, Join, LeftJoin, Limit, Lit, Order,
    Partition, Select, Sort, Var, Where, With, WithExternal, render  # FunSQL doesnt export

import DBInterface, Inflector, Tables
import PrettyTables: pretty_table
import UUIDs: UUID

"""Wrapper around a connection and lookup from its catalog.
See also [`AbstractModel`](@ref), [`TableQuery`](@ref)
"""
struct DB{T}
    connection::FunSQL.SQLConnection{T}
    sqlmap::Dict{Symbol,Tuple}
    # modellookup::Dict{Vector{Symbol},Type{AbstractModel}}   # should NOT reference AM, tables only
end
include("schema.jl")
"""DBInterface.connect is too low level for an ORM package"""
DB{T}(fname::String) where {T} =
    let conn = DBInterface.connect(FunSQL.DB{T}, fname)
        DB{T}(conn, sqlmap(conn))
    end

include("model.jl")
include("mutating.jl")

"""```jldoctest
julia> db[query::FunSQL.SQLNode]
SQLite.Query(...)
```"""
Base.getindex(db::DB, q::FunSQL.SQLNode) = DBInterface.execute(db.connection, q)

"""Allows for special query syntax and converts to an SQL Node when used in a query.
It also hold the type information to convert the query output back into your defined model.
You construct it like this:
```jldoctest
julia> MyModel[(x=3, y=[4,6]), z=3:5, date=""=>"2022-02-22", RelatedModel[name="%aa_bb%"]]
FunnyORM.TableQuery{MyModel}(...)
```
Pass it to DB:
```jldoctest
julia> db[MyModel[]]
Vector{MyModel}...
```
"""
struct TableQuery{T<:AbstractModel}
    type::Type{T}
    orclauses::Vector{NamedTuple}
    tqs::Vector{TableQuery}
    kwargs::Dict{Symbol,Any}
end

Base.getindex(::Type{T}, args...; kwargs...) where {T<:AbstractModel} =
    let orclauses = collect(filter(x -> x isa NamedTuple, args)),
        tqs = collect(filter(x -> x isa TableQuery, args)),
        pks = cat(filter(x -> x isa Union{Vector,Integer,UUID}, args)..., dims=1),
        kwargs = Dict{Symbol,Any}(kwargs)

        if !isempty(pks)
            pk(T) ∈ keys(kwargs) && @error "ambiguous primary key, you passed both:" pks kwargs[pk(T)]
            kwargs[pk(T)] = cat(pks..., dims=1)
        end
        # TODO: below should check if something not passed any filter
        length(orclauses) + length(tqs) > length(args) && @warn "Invalid argument, ignoring."
        TableQuery{T}(T, orclauses, tqs, kwargs)
    end


"""```jldoctest
julia> convert(FunSQL.AbstractSQLNode, Movie[type="wha"]) 
FunSQL.SQLNode(...)
```"""
Base.convert(::Type{FunSQL.AbstractSQLNode}, tq::TableQuery{T}) where {T<:AbstractModel} =
    let kwargs = collect(tq.kwargs)
        f(key) = getproperty(Get, key)
        cond(key, val::Pair{T,T}) where {T} = Fun.between(f(key), val[1], val[end])
        cond(key, val::AbstractRange) = Fun.between(f(key), val[1], val[end])
        cond(key, val::AbstractVector) = Fun.in(f(key), val...)
        cond(key, val::AbstractString) = ('%' in val || '_' in val) ? Fun.like(f(key), val) : f(key) .== val
        cond(key, val) = f(key) .== val
        query = From(tablename(T))
        for kwarg in kwargs
            query = query |> Where(cond(kwarg...))
        end
        for orclause in tq.orclauses
            query = query |> Where(Fun.or((
                cond(key, val) for (key, val) in pairs(orclause)
            )...))
        end
        # if !isempty(tq.pks)
        #     query = query |> Fun.in(f(pk(tq.type)), tq.pks...)
        # end
        for desc::TableQuery in tq.tqs
            _get_pk(n) = pk(T) in fieldnames(desc.type) ? getproperty(n, pk(T)) : getproperty(n, pk(desc.type))  # TODO: sqlmap 
            query = query |> Join(:other => desc, _get_pk(Get) .== _get_pk(Get.other))
        end
        !isempty(tq.tqs) && (query = query |> Group((Get(n) for n in fieldnames(T))...))
        Base.convert(FunSQL.SQLNode, query)
    end


_unpack(ntuple::NamedTuple, ::Type{T}) where {T<:AbstractModel} = T(ntuple...)

"""```jldoctest
julia> db[Movie[type="wha"], sql=Where(true)]
Vector{Movie}...
```"""
Base.getindex(db::DB, tq::TableQuery{T}, sql::FunSQL.SQLNode=Where(true)) where {T<:AbstractModel} =
    _unpack.(Tables.rowtable(db[tq|>sql]), T)::Vector{T}

precompile(Base.getindex, (DB, FunSQL.SQLNode))
end
