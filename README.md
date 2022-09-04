# ORMish package that you can use with FunSQL (WIP)

<!-- <details open><summary>Julia Code</summary>xx</details> -->

## Quickstart

Let's start with the example DB that FunSQL provides: 

```julia 
using FunnyORM, SQLite
download("https://github.com/MechanicalRabbit/ohdsi-synpuf-demo/releases/download/20210412/synpuf-10p.sqlite", "db.sqlite")
db = DB{SQLite.DB}("db.sqlite")

```
First we need a mapping. It's easiest to generate it by specifying the db, object name, and table name.
```julia
write("person.jl", (FunnyORM.generate_string(db, :Person, :person)))
include("person.jl")
Person
```
After you run this, you VSCode should show you what Person is here, and what fields it has, when you hover over it.

Now we can query the db like this: 
```julia
using DataFrames
db[Person[month_of_birth=[2, 4], person_source_value="%F%", year_of_birth=1900:1930]] |> DataFrame
```
AbstractVector maps to IN, AbstractRange to BETWEEN and AbstractString to LIKE if it contains _ or $.
Otherwise it's just =.

Under the hood it's just FROM .. WHERE ... queries.   (todo: is AND better than chaining WHERE?)
So if you want more SQL you can add a second argument and your data will get piped into it.
```julia
using FunSQL: Order, Get
db[Person[month_of_birth=[2, 4], person_source_value="%F%", year_of_birth=1900:1930], Order(Get.year_of_birth)] |> DataFrame
```

JOINs are WIP.