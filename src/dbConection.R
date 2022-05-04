# connection to MIMIC-server

#install.packages("RPostgres") # Install package
library(DBI)
connection <- dbConnect(RPostgres::Postgres(),
                 dbname = 'mimic', # name db for all the groups
                 host = 'mimic-server.postgres.database.azure.com',
                 port = 5432, # port standard of SMDB
                 user = 'postgres', # user for all the groups
                 password = 'securepass321.') # user for all the groups

dbListTables(connection) # show list tables in db
dbGetQuery(connection, "SELECT table_name FROM information_schema.tables;")
