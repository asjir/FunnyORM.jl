import FunSQL: SQLDialect

process_sql(s::AbstractString) =
    let nothingorcapture(x, idx=2) = isnothing(x) ? nothing : x.captures[idx]
        tname(s) = match(r"(CREATE\s+TABLE\s+\"?)((\w)+)(\"|\s|\()", s) |> nothingorcapture
        pkey(s) =
            let v1 = nothingorcapture(match(r"(PRIMARY\s+KEY\s*\(\s*\[?)((\w)+)\)(\]|\s|$|,)", s))
                v2 = nothingorcapture(match(r"((^|\()\s*\[?\s*)(\w+)(.*PRIMARY\s+KEY)"m, s))
                isnothing(v1) ? v2 : v1
            end
        fkeys(s) = Dict(map(x -> x.captures[2] => (x.captures[4], x.captures[6]),
            eachmatch(r"(FOREIGN\s+KEY\s*\(\s*\[?) (\w+) (\]?\s*\)\s*REFERENCES\s+\"?) (\w+) (\"?\s*\(\s*\[?) (\w+) (\]?\s*\)\s*) ($|,|\))"xm, s)))
        notnulls(s) = map(x -> x.captures[3],
            eachmatch(r" ((^|\(|,)\s*) (\w+) (.+NOT\s+NULL.*($|\)|,))"xm, s))

        Symbol(tname(s)) => (pkey(s), fkeys(s), notnulls(s))
    end

getpk(tname::Symbol, sqlmap::Dict{Symbol,Tuple}) = sqlmap[tname][1]

get_sqls(conn::DBInterface.Connection, dialectname::Symbol=SQLDialect(typeof(conn)).name) =
    [x.sql for x in DBInterface.execute(conn, "SELECT * FROM sqlite_schema") if !ismissing(x.sql)]
sqlmap(conn) = Dict(map(process_sql, get_sqls(conn))...)


precompile(process_sql, (String,))
precompile(getpk, (Symbol, Dict{Symbol,Tuple}))