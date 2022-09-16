# Saving

"""To save you'd write: `MyModel(db)(...)` 
Saver is the intermediate `MyModel(db)`.
You'd likely want to use either `MyModel(db)(kwargs)` or `MyModel(db)([namedtuples...])` for bulk inserts.
"""
mutable struct Saver{T<:AbstractModel}
    db::DB
    Model::Type{T}
    nextindex::Int64
end
Saver(db::DB, Model::Type, nextindex::Int32) = Saver(db, Model, Int64(nextindex))

"""Basically you can't *really* save without constructing AbstractModels because someone might have overriden defaults.
E.g. you might want your Julia code to give default timestamps, but your db doesnt do it so you put it in your Model definition.
Then we need to construct each before saving to make experience consistent.
"""
_save(saver::Saver{T}, model_s::Union{Vector{T},T}) where {T<:AbstractModel} =
    let execute = model_s isa Vector ? DBInterface.executemany : DBInterface.execute
        🐴(t) = model_s isa Vector ? getfield.(model_s, t) : getfield(model_s, t)
        vals = map(🐴, fieldnames(T))
        phs = join(("?" for _ in fieldnames(T)), ", ")
        execute(saver.db.connection, """INSERT INTO $(tablename(T)) VALUES ($phs)""", vals)
        inserted = saver.db[saver.Model[[🐴(pk(T));]]]  # semicolon here flattens 0 or 1 level to have 1 level deep pk query.
        model_s isa Vector ? inserted : only(inserted)
    end

new_pk(saver::Saver) =
    saver.nextindex > 0 ? saver.nextindex : rand(fieldtype(saver.Model, pk(saver.Model)))
new_pk(saver::Saver, n::Int64) =
    saver.nextindex > 0 ? [saver.nextindex:(saver.nextindex+n-1);] : rand(fieldtype(saver.Model, pk(saver.Model)), n)

withpk(Model::Type{T}, 🔑::Int64, kwargs::NamedTuple) where {T<:AbstractModel} =
    Model(; merge(kwargs, (pk(Model) => 🔑,))...)

(saver::Saver)(; kwargs...) = _save(saver, withpk(saver.Model, new_pk(saver), NamedTuple(kwargs)))

(saver::Saver)(kwargss::Vector{T}) where {T<:NamedTuple} =
    let models = withpk.(saver.Model, new_pk(saver, Int64(length(kwargss))), kwargss)
        _save(saver, models)
    end

"""AbstractModel(db) gives you a Saver struct"""
(Model::Type{T} where {T<:AbstractModel})(db) =
    let counting = fieldtype(Model, pk(Model)) <: Union{Missing,Integer},  # technically should make it not nullable
        adjust(currpk) = ismissing(currpk) ? 1 : currpk + 1,
        q = Model[] |> Group() |> Select(Agg.max(Get(pk(Model))))  # for getting current pk

        Saver(db, Model, (counting ? (db[q] |> first |> first |> adjust) : 0))
    end

# Updating
export @update

_update(db::DB, m::T, kwargs::NamedTuple) where {T<:AbstractModel} =
    let phs = join(("$key=?" for key in keys(kwargs)), ", ")
        # check that all kwargs are valid? 
        !isempty(kwargs) && DBInterface.execute(db.connection, """UPDATE $(tablename(T)) SET $phs WHERE $(pk(T))=$(pk(m));""", values(kwargs))
        only(db[T[pk(m)]])
    end

"""
Usage `@update db[itemtoupdate] key1=val1 key2=val2 ..`
# Examples
```jldoctest
julia> firstperson = first(db[Person[]]); firstperson.year_of_birth
1940
julia> @update db[firstperson] year_of_birth=1941; firstperson.year_of_birth
1941
```"""
macro update(dbm, kwargs...)
    @assert all(map(kw -> kw.head == :(=), kwargs))
    kwargs = Expr(:tuple, kwargs...)
    expr = @capture(dbm, db_[m_]) ? :($m = FunnyORM._update($db, $m, $kwargs)) : error("Updating syntax is `@update db[m] key1=value key1`")
    esc(expr)
end

"""
`db[oldmodel](update_kwargs...)` returns an updated model.\n
`db[model]()` will not run the update query, so `db[model]` is a closure to return the up-to-date model when called.
# Examples
```jldoctest
julia> firstperson = first(db[Person[]]); firstperson.year_of_birth
1940
julia> updated = db[firstperson](year_of_birth=1941); firstperson.year_of_birth, updated.year_of_birth
(1940, 1941)
"""
Base.getindex(db::DB, m::AbstractModel) = (; kwargs...) -> _update(db, m, NamedTuple(kwargs))


precompile(Base.getindex, (DB, AbstractModel))