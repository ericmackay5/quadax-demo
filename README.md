# Quadax ksqlDB Demo

### Terraform
Terraform is used to spin up and later destroy Confluent Cloud resources that will be used as part of this demonstration.

1. Modify the env.sh with your Confluent Cloud API Key and region. Then source those environment variables with:
#
    source env.sh
# 
Initialize Terraform

    terraform init
Plan the terraform deployment and check for errors

    terraform plan
Spin up resources

    terraform apply

### Retrieving secrets for demo purposes

    terraform output -raw client_key
    terraform output -raw sr_key



### Confluent Cloud REST Proxy
Modify the ccloud-kafka-rest.properties with your Bootstrap and Schema Registry Endpoints as well as their respective API keys retrieved from Terraform

    kafka-rest-start ccloud-kafka-rest.properties

### Topic Creation
In this demo, we will keep the topic creation manual. Use the UI to create a new topic with the name 'example' with one partition

### Produce Data via REST Proxy to example topic

    curl -X POST -H "Content-Type: application/vnd.kafka.json.v2+json" \
        --data '{"records":[{"value":{"foo":"bar"}}]}' "http://localhost:8082/topics/example"


### Parse out Patient Data from origin 'example' topic into a ksqlDB Stream

    CREATE STREAM patientsRaw
        (PAYLOAD ARRAY<STRUCT<Subscriber STRUCT<FirstName VARCHAR, 
        MiddleName VARCHAR,
        LastName VARCHAR,
        Suffix VARCHAR,
        DateOfBirth VARCHAR,
        Gender VARCHAR,
        MemberId INT,
        Street VARCHAR,
        Street2 VARCHAR,
        City VARCHAR,
        State VARCHAR,
        Zip INT,
        InsuredIndicator VARCHAR,
        IndividualRelationshipDefinition VARCHAR
        >>>)
        WITH (KAFKA_TOPIC = 'example',
            VALUE_FORMAT = 'JSON',
            PARTITIONS = 1);

### Flatten new ksqlDB stream and load data to a new topic
    CREATE STREAM patientsParsed 
    WITH (KAFKA_TOPIC = 'patientsParsed',
        VALUE_FORMAT = 'JSON',
        KEY_FORMAT = 'JSON',
        PARTITIONS = 1)
    AS SELECT 
    PAYLOAD[1]->Subscriber->FirstName AS FirstName,
    PAYLOAD[1]->Subscriber->MiddleName,
    PAYLOAD[1]->Subscriber->LastName AS LastName,
    PAYLOAD[1]->Subscriber->Suffix,
    PAYLOAD[1]->Subscriber->DateOfBirth,
    PAYLOAD[1]->Subscriber->Gender,
    PAYLOAD[1]->Subscriber->MemberId AS MemberId,
    PAYLOAD[1]->Subscriber->Street,
    PAYLOAD[1]->Subscriber->Street2,
    PAYLOAD[1]->Subscriber->City,
    PAYLOAD[1]->Subscriber->State,
    PAYLOAD[1]->Subscriber->Zip,
    PAYLOAD[1]->Subscriber->InsuredIndicator,
    PAYLOAD[1]->Subscriber->IndividualRelationshipDefinition
    FROM PATIENTSRAW
    PARTITION BY PAYLOAD[1]->Subscriber->MemberId;


### Create a table for patient information
    CREATE TABLE AS SELECT LATEST_BY_OFFSET(FirstName), LATEST_BY_OFFSET(LastName), MemberID from PatientsParsed
    GROUP BY MemberId 
    EMIT CHANGES;


### Create Patient Coverage Stream from existing 'example' topic

    CREATE STREAM patientCoverageRaw
        (PAYLOAD ARRAY<STRUCT<AlertResponse STRUCT<
            PayerCodeSubmitted VARCHAR,
            NewPayerFound BOOLEAN,
            NewPayerName VARCHAR,
            NewPayerCode INT,
            InsurancePlanSelectSuccess BOOLEAN,
            InsurancePlanSelectPayer VARCHAR,
            InsurancePlanSelectPlan VARCHAR,
            AlertResponseMessage ARRAY<STRING>
        >>>)
        WITH (KAFKA_TOPIC = 'example',
            VALUE_FORMAT = 'JSON',
            PARTITIONS = 1);

### Flatten new stream and load messages to a new kafka topic
    CREATE STREAM PatientCoverage_parsed 
    WITH (KAFKA_TOPIC = 'patientCoverageParsed',
        VALUE_FORMAT = 'JSON',
        PARTITIONS = 1)
    AS SELECT 
    PAYLOAD[1]->AlertResponse->PAYERCODESUBMITTED,
    PAYLOAD[1]->AlertResponse->NEWPAYERFOUND,
    PAYLOAD[1]->AlertResponse->NEWPAYERNAME,
    PAYLOAD[1]->AlertResponse->NEWPAYERCODE,
    PAYLOAD[1]->AlertResponse->INSURANCEPLANSELECTSUCCESS,
    PAYLOAD[1]->AlertResponse->INSURANCEPLANSELECTPAYER,
    PAYLOAD[1]->AlertResponse->INSURANCEPLANSELECTPLAN,
    EXPLODE(PAYLOAD[1]->AlertResponse->ALERTRESPONSEMESSAGE) AS PatientCoverage
    FROM patientCoverageRaw;

### Create a ksqlDB Table that aggregates Patient Coverage types
    CREATE TABLE MessageCount AS SELECT 
    PatientCoverage, count(*) AS countOfCoverageType FROM patientCoverageParsed 
    GROUP BY PatientCoverage EMIT CHANGES;
