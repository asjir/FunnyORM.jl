# ORMish package that you can use with FunSQL (WIP)

<!-- <details open><summary>Julia Code</summary>xx</details> -->

## Quickstart

Let's start with the example DB that FunSQL provides: 

```julia 
using FunnyORM, SQLite
download("https://github.com/MechanicalRabbit/ohdsi-synpuf-demo/releases/download/20210412/synpuf-10p.sqlite", "db.sqlite")
db = DB{SQLite.DB}("db.sqlite")

```
First we need the object-relational mapping. It's easiest to generate it by specifying the db, object name, and table name.
```julia
write("person.jl", FunnyORM.generate_string(db, :Person, :person))
include("person.jl")
Person
```
After you run this, you VSCode should show you what Person is, and what fields it has, when you hover over it.

Now we can query the db: 
```julia
using DataFrames
db[Person[month_of_birth=[2, 4], person_source_value="%F%", year_of_birth=1900:1930]] |> DataFrame
```
AbstractVector maps to IN, AbstractRange and Pair to BETWEEN and AbstractString to LIKE if it contains _ or $.
Otherwise it's =.

Also a named tuple in arguments is treated as an or, so in this case the following are equivalent:
```julia
Person[month_of_birth=[2, 4]]
Person[(month_of_birth=2, month_of_birth=4)]
```

Under the hood it's FROM .. WHERE ... queries.
If you want more SQL you can add a second argument and it will work as if your data got piped into it.
```julia
using FunSQL: Order, Get
db[Person[month_of_birth=[2, 4]], Order(Get.year_of_birth)] |> DataFrame
```
In the examples above we create a vector of objects and convert to DataFrame for printing. (Tables interface WIP)
To skip creation of objects you can do:
```julia
using FunSQL: Order, Get
db[Person[month_of_birth=[2, 4]] |> Order(Get.year_of_birth)] |> DataFrame
```
And be able to get any fields aggregations with sql etc.

You can also query by relations, though `contraint ... foreign key...` is not supported yet - the column names simply need to match.

```julia
write("visit.jl", FunnyORM.generate_string(db, :Visit, :visit_occurrence))
include("visit.jl")

db[Person[Visit[visit_end_date="" => "2008-04-13"]]]
```
This will give you people who had visits that ended before 13th Apr 2008.

For many-to-many relationship you need to have an object for e.g. `PersonVisit` in this case and do `Person[PersonVisit[Visit[...]]]`.

And if you use JET then it will pick up some errors, like field name being wrong here:
```julia
db[Person[month_of_birth=[2, 4]]][1].year_if_birth
```
