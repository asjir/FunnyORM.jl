using Test, SQLite, FunnyORM, DBInterface
import Tables: rowtable

using FunSQL: From, ReferenceError

using Aqua, LaTeXStrings
Aqua.test_all(FunnyORM, ambiguities=(; exclude=[LaTeXStrings.getindex]))

@testset "db operations" begin
    dir = mkdir(tempname())
    db = FunnyORM.DB{SQLite.DB}("$dir/tempdb.db")
    person_sql = """CREATE TABLE person(
        Id INT NOT NULL,
        LastName varchar(255) NOT NULL,
        Age int,
        PRIMARY KEY (Id)    
    );"""
    DBInterface.execute(db.connection, person_sql)

    DBInterface.execute(db.connection,
        """ALTER TABLE person ADD COLUMN FirstName varchar(255);""")

    DBInterface.execute(db.connection,
        """CREATE TABLE home(
            Id INT NOT NULL,
            OwnerId INT NOT NULL,
            PRIMARY KEY (Id),
            FOREIGN KEY (OwnerId) REFERENCES person(Id)
        );""")
    # DBInterface.execute(db.connection,
    #     """INSERT INTO person VALUES (1, "whaat", 3, "haha");""")

    @testset "generation" begin
        @test_throws ReferenceError FunnyORM.generate_file(db, :Person, tablename=:person, path="$dir/person.jl")
        db = FunnyORM.DB{SQLite.DB}("$dir/tempdb.db")
        @test :person in keys(FunnyORM.DB{SQLite.DB}("$dir/tempdb.db").sqlmap)
        @test begin
            include(FunnyORM.generate_file(db, :Person, tablename=:person, path="$dir/person.jl"))
            true
        end
        @test FunnyORM.process_sql(person_sql)[2][[1, 3]] == ("Id", ["Id", "LastName"])
        @test pk(Person) == :Id
        @test Person(db)(LastName="Bob").LastName == "Bob"
        @test rowtable(db[Person[LastName="Bob"]])[1].LastName == "Bob"
        @test Person(db)([(LastName="Man",), (LastName="Woman",)])[1].LastName == "Man"
        bob = only(db[Person[LastName="Bob"]])
        @test length(db[Person[]]) == 3
        @test length(db[Person[[1, 2]]]) == 2

        @test only(db[Person[bob]]) == bob
        @test only(db[Person[[bob]]]) == bob
        @test length(db[Person[LastName="Man"]]) == 1
        guy = db[Person[LastName="Man"]] |> only
        @test rowtable(guy)[1].LastName == "Man"
        guyer = db[guy]
        @test guyer().FirstName === missing
        @test (@update db[guy] FirstName = "My").FirstName == "My"
        @test guyer().FirstName == "My"
        @test length(db[Person[LastName=["Man", "Woman"]]]) == 2
        include(FunnyORM.generate_file(db, :Home, tablename=:home, path="$dir/home.jl"))
        @test (Home(db)(OwnerId=1)).OwnerId == 1
        @test db[Person[Home[1]]][1].LastName == "Bob"
        home = db[Home[OwnerId=1]]
        @test db[Person[home]][1].LastName == "Bob"
        @test_throws UndefKeywordError Home(db)()
    end
end
