using Test, SQLite, FunnyORM, DBInterface
import Tables: rowtable

using FunSQL: From

@testset "db operations" begin
    dir = mkdir(tempname())
    db = FunnyORM.DB{SQLite.DB}("$dir/tempdb.db")
    DBInterface.execute(db.connection,
        """CREATE TABLE person(
            Id INT NOT NULL,
            LastName varchar(255) NOT NULL,
            Age int,
            PRIMARY KEY (Id)    
        );""")
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
        db = FunnyORM.DB{SQLite.DB}("$dir/tempdb.db")
        @test :person in keys(db.sqlmap)
        @test DBInterface.execute(db.connection, "SELECT * FROM person") |> rowtable |> isempty
        @test begin
            include(FunnyORM.generate_file(db, :Person, tablename=:person, path="$dir/person.jl"))
            true
        end
        @test pk(Person) == :Id
        @test Person(db)(LastName="Bob").LastName == "Bob"
        @test Person(db)([(LastName="Man",), (LastName="Woman",)])[1].LastName == "Man"
        guy = db[Person[LastName="Man"]] |> only
        @test (@update db[guy] FirstName = "My").FirstName == "My"
    end
end
