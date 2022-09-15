# Saving

"""To save you'd write: `MyModel(db)(...)` 
Saver is the intermediate `MyModel(db)`.
You'd likely want to use either `MyModel(db)(kwargs)` or `MyModel(db)([namedtuples...])` for bulk inserts.
"""
mutable struct Saver{T<:AbstractModel}
    db::DB
    Model::Type{T}
    nextindex::Int
end

_callsaver(saver::Saver, closure::Function, cnt::Int=1, returnvec=false) =
    let T = saver.Model
        vals = map(fldn -> closure(fldn, new_pk), fieldnames(T))
        phs = join(("?" for _ in vals), ", ")
        execute = cnt == 1 ? DBInterface.execute : DBInterface.executemany
        execute(saver.db.connection, """INSERT INTO $(tablename(T)) VALUES ($phs)""", vals)
        saver.nextindex += (saver.nextindex > 0 ? cnt : 0)
        pks = [closure(pk(T), new_pk);]
        inserted = saver.db[saver.Model[pks]]
        returnvec ? inserted : only(inserted)
    end

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
new_pk(saver::Saver, n::Int) =
    saver.nextindex > 0 ? [saver.nextindex:(saver.nextindex+n-1);] : rand(fieldtype(saver.Model, pk(saver.Model)), n)

withpk(Model::Type{T}, 🔑, kwargs::NamedTuple) where {T<:AbstractModel} =
    Model(; merge(kwargs, (pk(Model) => 🔑,))...)

(saver::Saver)(; kwargs...) = _save(saver, withpk(saver.Model, new_pk(saver), kwargs.data))

(saver::Saver)(kwargss::Vector{T}) where {T<:NamedTuple} =
    let models = withpk.(saver.Model, new_pk(saver, length(kwargss)), kwargss)
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
        DBInterface.execute(db.connection, """UPDATE $(tablename(T)) SET $phs WHERE $(pk(T))=$(pk(m));""", values(kwargs))
        only(db[T[pk(m)]])
    end

"""
Usage db[itemtoupdate] key1=val1 key2=val2 ..
# Examples
```jldoctest

julia> @update db[acdc] Title="yoo"
Album
┌─────────┬────────┬──────────┐
│ AlbumId │  Title │ ArtistId │
│   Int64 │ String │    Int64 │
├─────────┼────────┼──────────┤
│       1 │    yoo │        1 │
└─────────┴────────┴──────────┘
julia> acdc
Album
┌─────────┬────────┬──────────┐
│ AlbumId │  Title │ ArtistId │
│   Int64 │ String │    Int64 │
├─────────┼────────┼──────────┤
│       1 │    yoo │        1 │
└─────────┴────────┴──────────┘

```"""
macro update(dbm, kwargs...)
    @assert all(map(kw -> kw.head == :(=), kwargs))
    kwargs = Expr(:tuple, kwargs...)
    expr = @capture(dbm, db_[m_]) ? :($m = FunnyORM._update($db, $m, $kwargs)) : error("Updating syntax is `@update db[m] key1=value key1`")
    esc(expr)
end