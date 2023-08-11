# ORM package that you can use with FunSQL

[![Dev Documentation][docs-dev-img]][docs-dev-url]
[![Build Status][ci-img]][ci-url]
[![Code Coverage Status][codecov-img]][codecov-url]
[![MIT License][license-img]][license-url]
[![Aqua QA](https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)


## Motivating example

FunSQL.jl allows you to build better queries than, say SQLAlchemy, but it doesn't provide an Object-Relational Mapping.
This package does, so that you're able to write:
```julia 
julia> let f(x) = x |> Join(:new => x |> Group(Get.gender_concept_id) |> Select(Agg.max(Get.year_of_birth), Get.gender_concept_id), Fun.and(Get.gender_concept_id .== Get.new.gender_concept_id, Get.year_of_birth .== Get.new.max)) 
       db[Person, f]  
       end
```
Which for each gender will pick the youngest people by year, and return `Person` struct for each.

These structs are generated to be included in your code, so `VSCode` can show the definition with fields when you hover over them. And `JET.jl` can do type-checking, e.g. picking up the typo here:
```julia
db[Person[month_of_birth=[2, 4]]][1].year_if_birth
```
## Status

* Only supports Integer ids.
* Only supports SQLite.
* Errors with Transducers.jl

## Walkthrough

We start with the example DB that FunSQL provides: 

```julia 
using FunnyORM, SQLite
download("https://github.com/MechanicalRabbit/ohdsi-synpuf-demo/releases/download/20210412/synpuf-10p.sqlite", "db.sqlite")
db = FunnyORM.DB{SQLite.DB}("db.sqlite")

```
First we need the object-relational mapping. It's easiest to generate it by specifying the db, object name, and table name.
```julia
FunnyORM.generate_file(db, :Person, tablename=:person)
include("models/person.jl")
Person
```
After you run this, you VSCode should show you what Person is, and what fields it has, when you hover over it. 


<details><summary>About defaults</summary>

If a field can be `Missing`, the generated class will contain default `missing` for it. For the rest no default is set, so you may wish to edit the generated file.

It will try to link to tablename, which by default is lowercase, pluralised model name. 

</details>
Now we can query the db.

```julia
using DataFrames
db[Person[month_of_birth=[2, 4], person_source_value="%F%", year_of_birth=1900:1930]]
```
If you know SQL a Vector is `IN`, AbstractRange and Pair `BETWEEN` and AbstractString to either `LIKE` if it contains _ or $, or `=`.

Also a named tuple in arguments is treated as an `OR`, so in this case the following are equivalent:
```julia
Person[month_of_birth=[2, 4]]
Person[(month_of_birth=2, month_of_birth=4)]
```

Under the hood it's converted to SQL queries.
You can add a second argument to `getindex` and it will pass your query into it.
```julia
using FunSQL: Order, Get
db[Person[month_of_birth=[2, 4]], Order(Get.year_of_birth)]
```
In the examples above we create a vector of objects and convert to DataFrame for printing.
To skip creation of objects you can replace `,` with `|>`:
```julia
using FunSQL: Order, Get
db[Person[month_of_birth=[2, 4]] |> Order(Get.year_of_birth)] |> DataFrame
```
And be able to use FunSQL to further, e.g:
* only select a subset fields,
* join tables
* aggregate

You can also query by relations, though the column names simply need to match. `contraint ... foreign key...` is not supported yet. Here's an example:

```julia
FunnyORM.generate_file(db, :Visit, tablename=:visit_occurrence)
include("models/visit_occurrence.jl")

db[Person[Visit[visit_end_date="" => "2008-04-13"]]]
```
This will give you people who had visits that ended before 13th Apr 2008 (inclusive).

For many-to-many relations you need to have an object for e.g. `PersonVisit` in this case and do `Person[PersonVisit[Visit[...]]]`. 
Also if you already had a `vis::Visit` then `vis == db[vis]` so you can write `Person[PersonVisit[vis]]` to get people that went on that visit.

## Mutating:

### Creating new objects:

```julia
# single insert - returns new Person
Person(db)(gender_concept_id=8532, month_of_birth=11)
# bulk insert - returns Vector{Person}
Person(db)([(gender_concept_id=8532, month_of_birth=11), (gender_concept_id=1111,)])
```
### Updating objects

Here you can use a macro:

```julia
# grab the latest insert
example = db[Person[year_of_birth=1940]] |> first
@update db[example] day_of_birth = 10 month_of_birth = 3
example.day_of_birth == 10  # true

# Warning! It only updates the reference you call it with, i.e:
old = example
@update db[example] day_of_birth = 15
example.day_of_birth == 15, example.day_of_birth == 10  # both true
```

Or using `db[model](kwargs)` syntax:
```julia
updated = db[example](year_of_birth=1941)
example.year_of_birth == 1940, updated.year_of_birth == 1941  # both true
```
# still TODO:

* db.sqlmap for relationships
* UUIDs, e.g. with PSQL
* get_sqls for dbs other than sqlite
* dates
  
[docs-dev-img]: https://img.shields.io/badge/docs-dev-blue.svg
[docs-dev-url]: https://asjir.github.io/FunnyORM.jl/dev/
[docs-rel-img]: https://img.shields.io/badge/docs-stable-green.svg
[docs-rel-url]: https://asjir.github.io/FunnyORM.jl/stable/
[ci-img]: https://github.com/asjir/FunnyORM/workflows/CI/badge.svg
[ci-url]: https://github.com/asjir/FunnyORM/actions?query=workflow%3ACI+branch%3Amain
[codecov-img]: https://codecov.io/gh/asjir/FunnyORM/branch/main/graph/badge.svg
[codecov-url]: https://codecov.io/gh/asjir/FunnyORM
[license-img]: https://img.shields.io/badge/license-MIT-blue.svg
[license-url]: https://raw.githubusercontent.com/asjir/FunnyORM/main/LICENSE.md
