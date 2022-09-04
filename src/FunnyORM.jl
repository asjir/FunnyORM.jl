module FunnyORM

import FunSQL: FunSQL, Agg, Append, As, Asc, Bind, Define, Desc, Fun, From, Get,
    Group, Highlight, Iterate, Join, LeftJoin, Limit, Lit, Order,
    Partition, Select, Sort, Var, Where, With, WithExternal, render  # FunSQL doesnt export

import DBInterface, SQLite, Inflector, Tables
import PrettyTables: pretty_table
export DB

include("model.jl")

"""wrapper around a connection and lookup from its catalog"""
struct DB{T}
    connection::FunSQL.SQLConnection{T}
    modellookup::Dict{Vector{Symbol},Type{AbstractModel}}
end

"""DBInterface.connect is too low level for an ORM package"""
DB{T}(fname::String) where {T} = DB{T}(DBInterface.connect(FunSQL.DB{T}, fname), Dict{Vector{Symbol},Type{AbstractModel}}())


"""```jldoctest
julia> db[query::FunSQL.SQLNode] = sqlresult
```"""
Base.getindex(db::DB, q::FunSQL.SQLNode) = DBInterface.execute(db.connection, q)

struct TableQuery{T<:AbstractModel}
    type::Type{T}
    kwargs::Dict{Symbol,Any}
end
# Base.getindex(::Type{T}) where {T<:AbstractModel} = From(tablename(T)),   # HERE
Base.getindex(::Type{T}; kwargs...) where {T<:AbstractModel} = TableQuery{T}(T, kwargs)
"""```jldoctest
julia> Movie[type="wha"] = query::FunSQL.SQLNode
```"""
Base.convert(::Type{FunSQL.AbstractSQLNode}, tq::TableQuery{T}) where {T<:AbstractModel} =
    let kwargs = collect(tq.kwargs)
        _get(key) = getproperty(Get, key)
        _Where(key, val::AbstractRange) = Where(Fun.between(_get(key), val[1], val[end]))
        _Where(key, val::AbstractVector) = Where(Fun.in(_get(key), val...))
        _Where(key, val::AbstractString) = ('%' in val || '_' in val) ? Where(Fun.like(_get(key), val)) : _Where(key, val)
        _Where(key, val) = Where(_get(key) .== val)
        from = From(tablename(T))
        for kwarg in kwargs
            from = from |> _Where(kwarg...)
        end
        Base.convert(FunSQL.SQLNode, from)
    end


_unpack(::Type{T}, ntuple::NamedTuple) where {T<:AbstractModel} = T(ntuple...)

"""```jldoctest
julia> db[Movie[type="wha"], sql=Where(true)] = modelresult::Vector{Movie}
```"""
Base.getindex(db::DB, tq::TableQuery{T}, sql::FunSQL.SQLNode=Where(true)) where {T<:AbstractModel} =
    _unpack.(T, Tables.rowtable(db[tq|>sql]))::Vector{T}

generate(db::DB, ::Type{T}) where {T<:AbstractModel} =
# this will be for validation
    let table::FunSQL.SQLTable = db.connection.catalog[tablename(T)]
        3
    end


end