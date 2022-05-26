# # Create Cohort Table
# sql_cohort_table <- "CREATE TABLE @cdmDatabaseSchema.@target_cohort_table (
# 			          cohort_definition_id integer NOT NULL,
# 			          subject_id integer NOT NULL,
# 			          cohort_start_date date NOT NULL,
# 			          cohort_end_date date NOT NULL );"
# 
# sql_cohort_table <- SqlRender::render(sql_cohort_table, 
#                                       cdmDatabaseSchema=dbSchema,
#                                       target_cohort_table=target_cohort_table)
# 
# DatabaseConnector::executeSql(connection, 
#                               sql_cohort_table)

pathToDriver <- "/home/ohdsi/workdir/Trabajo_Final"
# Download drivers
# DatabaseConnector::downloadJdbcDrivers(pathToDriver = pathToDriver, 
#                                        dbms = "postgresql")

# substitute variables
filePath <- "~/workdir/Trabajo_Final/prevalent_heart_disease.sql"
dbSchema = "omop"
dbName <- "mimic"
target_cohort_table = "kamila_cohorts"
sql <- SqlRender::readSql(filePath)
sql <- SqlRender::render(sql, cdm_database_schema=paste0(dbSchema),
                              target_cohort_table=target_cohort_table,
                              target_database_schema=dbSchema,
                              vocabulary_database_schema=dbSchema,
                              target_cohort_id="2")

# manually replace codesets
gsub("#Codesets", paste0(dbSchema, ".codesets"), sql)

# Translate to PSQL
sql_psql_heart_failure <- SqlRender::translate(sql = sql, targetDialect = "postgresql")


# outcome Cohort
filePath <- "~/workdir/Trabajo_Final/any_death.sql"
sql <- SqlRender::readSql(filePath)
sql <- SqlRender::render(sql, cdm_database_schema=dbSchema,
                         target_cohort_table=target_cohort_table,
                         target_database_schema=dbSchema,
                         target_cohort_id="3")

# manually replace codesets
gsub("#Codesets", paste0(dbSchema, ".codesets"), sql)

# Translate to PSQL
sql_psql_any_death <- SqlRender::translate(sql = sql, targetDialect = "postgresql")


# Connect to Database
connectionDetails <- DatabaseConnector::createConnectionDetails(dbms = "postgresql",
                                                                user = 'postgres',
                                                                server = 'mimic-server.postgres.database.azure.com/mimic',
                                                                port = 5432,
                                                                password = '******',
                                                                pathToDriver=pathToDriver)


connection <- DatabaseConnector::connect(connectionDetails)

 
# Run the Target Cohort
DatabaseConnector::executeSql(connection,
                              sql_psql_heart_failure)


# Run the Outcome Cohort
DatabaseConnector::executeSql(connection,
                              sql_psql_any_death)

# Check the number of patients
sql <- "SELECT 
        COUNT(*) AS COUNTS 
         FROM 
         omop.kamila_cohorts 
          WHERE 
         cohort_definition_id = 2
              "
df <- DatabaseConnector::querySql(connection, sql)
print("Target Cohort Counts")
print(df)


sql <- "SELECT 
        COUNT(*) AS COUNTS 
         FROM 
         omop.kamila_cohorts 
          WHERE 
         cohort_definition_id = 3
              "
df <- DatabaseConnector::querySql(connection, sql)
print("Outcome Cohort Counts")
print(df)
DatabaseConnector::disconnect(connection)


# now the PLP setting

options(java.parameters = "-Xmx2000m")

covariateSettings <- FeatureExtraction::createCovariateSettings(useDemographicsGender = TRUE,
                                                                useDemographicsAge = TRUE,
                                                                useConditionGroupEraLongTerm = TRUE,
                                                                useConditionGroupEraAnyTimePrior = TRUE,
                                                                useDrugGroupEraLongTerm = TRUE,
                                                                useDrugGroupEraAnyTimePrior = TRUE,
                                                                useVisitConceptCountLongTerm = TRUE,
                                                                longTermStartDays = -365,
                                                                endDays = -1)


databaseDetails <- PatientLevelPrediction::createDatabaseDetails(connectionDetails = connectionDetails,
                                                                  cdmDatabaseSchema = dbSchema,
                                                                  cdmDatabaseName = dbName,
                                                                  cohortDatabaseSchema = dbSchema,
                                                                  cohortTable = target_cohort_table,
                                                                  cohortId = 2,
                                                                  outcomeDatabaseSchema = dbSchema,
                                                                  outcomeTable = target_cohort_table,
                                                                  outcomeIds = 3,
                                                                  cdmVersion = 5
                                                                  )


restrictPlpDataSettings <- PatientLevelPrediction::createRestrictPlpDataSettings(sampleSize = 10000)

plpData <- PatientLevelPrediction::getPlpData(databaseDetails = databaseDetails,
                                              covariateSettings = covariateSettings,
                                              restrictPlpDataSettings = restrictPlpDataSettings
)

PatientLevelPrediction::savePlpData(plpData, "/home/ohdsi/workdir/Trabajo_Final/death_model")

populationSettings <- PatientLevelPrediction::createStudyPopulationSettings(washoutPeriod = 0,
                                                                            firstExposureOnly = TRUE,
                                                                            removeSubjectsWithPriorOutcome = TRUE,
                                                                            priorOutcomeLookback = 99999,
                                                                            riskWindowStart = 1,
                                                                            riskWindowEnd = 90,
                                                                            startAnchor =  'cohort start',
                                                                            endAnchor =  'cohort start',
                                                                            minTimeAtRisk = 30,
                                                                            requireTimeAtRisk = TRUE,
                                                                            includeAllOutcomes = TRUE
                                                                            )

# Spliting the data into training/validation/testing datasets

splitSettings <- PatientLevelPrediction::createDefaultSplitSetting( trainFraction = 0.75,
                                                                    testFraction = 0.25,
                                                                    type = 'stratified',
                                                                    nfold = 5, 
                                                                    splitSeed = 1234
                                                                   )

# Preprocessing the training data

sampleSettings <- PatientLevelPrediction::createSampleSettings()
featureEngineeringSettings <- PatientLevelPrediction::createFeatureEngineeringSettings()


preprocessSettings <- PatientLevelPrediction::createPreprocessSettings(
  minFraction = 0.01, 
  normalize = T, 
  removeRedundancy = T
)


#Model Development
lrModel <- PatientLevelPrediction::setLassoLogisticRegression()

lrResults <- PatientLevelPrediction::runPlp(
  plpData = plpData,
  outcomeId = 3, 
  analysisId = 'Test',
  analysisName = 'Demonstration of runPlp for training single PLP models',
  populationSettings = populationSettings, 
  splitSettings = splitSettings,
  sampleSettings = sampleSettings, 
  featureEngineeringSettings = featureEngineeringSettings, 
  preprocessSettings = preprocessSettings,
  modelSettings = lrModel,
  logSettings = PatientLevelPrediction::createLogSettings(), 
  executeSettings = PatientLevelPrediction::createExecuteSettings(
    runSplitData = T, 
    runSampleData = T, 
    runfeatureEngineering = T, 
    runPreprocessData = T, 
    runModelDevelopment = T, 
    runCovariateSummary = T
  ), 
  saveDirectory = file.path(getwd(), '/home/ohdsi/workdir/Trabajo_Final/Test')
)

library(PatientLevelPrediction)
library(dplyr)
viewPlp(lrResults)
