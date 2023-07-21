import FunSQL: SQLDialect

process_sql(s::AbstractString) =
    let nothingorcapture(x, idx=2) = isnothing(x) ? nothing : x.captures[idx]
        nameandpkey = r"(?ix)                   # Ignore case and enable comments
            \bCREATE\s+TABLE\s+(\w+)\s*   # Match 'CREATE TABLE table_name' and capture table_name
            \(                            # Match the opening parenthesis
            (?:                           # Non-capturing group for column definitions
                \s*(\w+)\s*               # Capture column name
                (?:\s+[^,\n]+\s*PRIMARY\s+KEY\s*(?:[^,\n]+)?)?  # Match optional 'PRIMARY KEY' column constraint
                ,?                        # Match the column separator (comma) if present
            )+                            # Repeat column definitions one or more times
            \s*\);                        # Match ');' with optional whitespace before it
        "
        tname(s) = nothingorcapture(match(nameandpkey, s), 1)
        pkey(s) = nothingorcapture(match(nameandpkey, s), 2)
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