import MacroTools: @capture, postwalk

export AbstractModel, pk

"""AbstractModel is the base type for your models.
You should not instantiate your model manually.

You get it with a:
* query: `db[MyModel[conditions...]][idx]`
* insertion: `MyModel(db)(kwargs)`
* updating: `newmodel = db[oldmodel](update_kwargs...)` or `@update db[model] key1=val1 key2=val2 ...`
"""
abstract type AbstractModel end

_show(io, x) = (show(io, typeof(x)); println(stdout); pretty_table(io, Tables.rowtable(x)))
Base.show(io::IO, t::T) where {T<:AbstractModel} = _show(io, t)
Base.show(io::IO, ::MIME"text/plain", t::T) where {T<:AbstractModel} = _show(io, t)
Base.show(io::IO, ts::Vector{T}) where {T<:AbstractModel} = _show(io, ts)
Base.show(io::IO, ::MIME"text/plain", ts::Vector{T}) where {T<:AbstractModel} = _show(io, ts)

Base.NamedTuple(m::AbstractModel) = NamedTuple([name => getfield(m, name) for name in fieldnames(typeof(m))])  # not sure if needed
Tables.rows(ts::Vector{T}) where {T<:AbstractModel} = NamedTuple.(ts)
Tables.rows(t::AbstractModel) = [NamedTuple(t)]

pk(m::AbstractModel) =
    let 🐴(x::Int32) = convert(Int64, x), 🐴(x) = x
        🐴(getfield(m, pk(typeof(m))))
    end

### Generating

tablename = Symbol ∘ Inflector.to_plural ∘ string
generate(db::DB, genmodelname::Symbol; tablename::Symbol=tablename(genmodelname)) =  # maybe this can use PRIMARY KEY / FOREIGN KEY for auto pk etc.
    let lcsymbol = Symbol ∘ lowercase ∘ string
        (tablename ∉ keys(db.sqlmap) && lcsymbol(tablename) ∈ keys(db.sqlmap)) && begin
            @info "$tablename not found in the db, but $(lcsymbol(tablename)) yes, so mapping to that"
            tablename = lcsymbol(tablename)
        end
        res = try
            db[From(tablename)]
        catch e
            e isa FunSQL.ReferenceError && @error "$tablename not found in the db.
            Try specifying the `gentablename` keyword argument. 
            If the table has just been created, you need to reset the connection with new FunnyORM.DB object."
            rethrow(e)
        end

        mapped = tablename ∈ keys(db.sqlmap)
        # TODO: also need to generate references at this point
        can_get_pk = mapped && db.sqlmap[tablename][1] ∈ db.connection.catalog[tablename].column_set
        allowsmissing(name) = mapped ? string(name) ∉ db.sqlmap[tablename][3] : true
        can_get_pk || @warn "couldn't infer pk for table $genmodelname, defaulting to $(first(res.names))"
        structdef = :(struct $genmodelname <: AbstractModel end)
        filtermissing(typ) =
            :(Union{$(filter(!=(Missing), Base.uniontypes(typ))...)})
        fielddef(name, typ) =
            allowsmissing(name) ? :($name::$(Union{typ,Missing}) = missing) : :($name::$(filtermissing(typ)))
        # also need to handle UUIDs/conversions here at some point.
        structdef.args[3].args = map(fielddef, res.names, res.types)  # fields
        :((
            Base.@kwdef $structdef;
            FunnyORM.tablename(::Type{$genmodelname}) = Symbol($(string(tablename)));
            FunnyORM.pk(::Type{$genmodelname}) =
                Symbol($(string(can_get_pk ? db.sqlmap[tablename][1] : first(res.names))))
        ))
    end

generate_string(db::DB, genmodelname::Symbol; tablename::Symbol=tablename(genmodelname)) =
    let expr = Base.remove_linenums!(FunnyORM.generate(db, genmodelname; tablename))
        bare_string = join(map(string, expr.args), "\n")
        strip(replace(bare_string, r"#=.*=#" => "", "\n    " => "\n"))
    end

"""
Using the databsase schema
"""
generate_file(db::DB, genmodelname::Symbol; tablename::Symbol=tablename(genmodelname), path="models/$tablename.jl") =
    let _ = mkpath(dirname(path))
        write(path, generate_string(db, genmodelname; tablename))
        path
    end

precompile(generate, (DB, Symbol, Symbol))
precompile(generate_string, (DB, Symbol, Symbol))