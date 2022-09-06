module FunnyORM

import FunSQL: FunSQL, Agg, Append, As, Asc, Bind, Define, Desc, Fun, From, Get,
    Group, Highlight, Iterate, Join, LeftJoin, Limit, Lit, Order,
    Partition, Select, Sort, Var, Where, With, WithExternal, render  # FunSQL doesnt export

import DBInterface, SQLite, Inflector, Tables
import PrettyTables: pretty_table
export DB


"""wrapper around a connection and lookup from its catalog"""
struct DB{T}
    connection::FunSQL.SQLConnection{T}
    # modellookup::Dict{Vector{Symbol},Type{AbstractModel}}
end
include("model.jl")

"""DBInterface.connect is too low level for an ORM package"""
DB{T}(fname::String) where {T} = DB{T}(DBInterface.connect(FunSQL.DB{T}, fname), Dict())

"""```jldoctest
julia> db[query::FunSQL.SQLNode] = sqlresult
```"""
Base.getindex(db::DB, q::FunSQL.SQLNode) = DBInterface.execute(db.connection, q)

struct TableQuery{T<:AbstractModel}
    type::Type{T}
    orclauses::Vector{NamedTuple}
    tqs::Vector{TableQuery}
    kwargs::Dict{Symbol,Any}
end
# Base.getindex(::Type{T}) where {T<:AbstractModel} = From(tablename(T)),   # HERE
Base.getindex(::Type{T}, args...; kwargs...) where {T<:AbstractModel} =
    let orclauses = collect(filter(x -> x isa NamedTuple, args)), tqs = collect(filter(x -> x isa TableQuery, args))
        length(orclauses) + length(tqs) > length(args) && @warn "Invalid argument, ignoring."
        TableQuery{T}(T, orclauses, tqs, kwargs)
    end


"""```jldoctest
julia> convert(FunSQL.AbstractSQLNode, Movie[type="wha"]) = query::FunSQL.SQLNode
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

        for desc::TableQuery in tq.tqs
            _get_pk(n) = pk(T) in fieldnames(desc.type) ? getproperty(n, pk(T)) : getproperty(n, pk(desc.type))  # TODO: many to many 
            query = query |> Join(:other => desc, _get_pk(Get) .== _get_pk(Get.other))
        end
        !isempty(tq.tqs) && query = query |> Group((Get(n) for n in fieldnames(T))...)
        Base.convert(FunSQL.SQLNode, query)
    end


_unpack(ntuple::NamedTuple, ::Type{T}) where {T<:AbstractModel} = T(ntuple...)

"""```jldoctest
julia> db[Movie[type="wha"], sql=Where(true)] = modelresult::Vector{Movie}
```"""
Base.getindex(db::DB, tq::TableQuery{T}, sql::FunSQL.SQLNode=Where(true)) where {T<:AbstractModel} =
    _unpack.(Tables.rowtable(db[tq|>sql]), T)::Vector{T}


# generate(db::DB, ::Type{T}) where {T<:AbstractModel} =
# # this will be for validation
#     let table::FunSQL.SQLTable = db.connection.catalog[tablename(T)]
#         3
#     end

# multi object code
# import NamedTupleTools: select
# import DataStructures: DefaultOrderedDict
# _prefixize(prefix::Symbol, target::Symbol) = Symbol(string(prefix) * string(target))

# _unpack(ntuple::NamedTuple, ::Type{T}, ::Type{U}) where {T,U<:AbstractModel} =
#     let valselect(ntuple, prefix, type) = values(select(ntuple, _prefixize.(prefix, fieldnames(type))))  # this is very meh
#         T(valselect(ntuple, :left_, T)...), U(valselect(ntuple, :right_, U)...)
#     end

# Base.getindex(db::DB, tq::TableQuery{T}, tq2::TableQuery{U}, sql::FunSQL.SQLNode=Where(true)) where {T,U<:AbstractModel} =
#     let get_pk(n) = getproperty(n, pk(T))
#         sel = Select([_prefixize(:left_, fname) => getproperty(Get, fname) for fname in fieldnames(T)]...,
#             [_prefixize(:right_, fname) => getproperty(Get.other, fname) for fname in fieldnames(U)]...)
#         # Tables.rowtable(db[tq|>Join(:other => tq2, get_pk(Get) .== get_pk(Get.other))|>sql|>sel])
#         query = db[tq|>Join(:other => tq2, get_pk(Get) .== get_pk(Get.other))|>sql|>sel]
#         tuples = _unpack.(Tables.rowtable(query), T, U)
#         aggregate(tuples) =
#             let
#                 dict = DefaultOrderedDict{T,Vector{U}}(() -> Vector{U}())
#                 for (left, right) in tuples
#                     push!(dict[left], right)
#                 end
#                 return dict
#             end
#         aggregate(tuples)
#     end

# setmany2many!(db::DB, types=subtypes(AbstractModel)) =
#     let pks = pk.(types), flags = zeros(Int, length(types)), fieldnamess = fieldnames.(types)
#         for (i, currpk) in enumerate(pks)
#             flags[i+1:end] += currpk .∈ fieldnamess[i+1:end]
#         end
#     end

end