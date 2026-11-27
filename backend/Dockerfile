FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /w
COPY pom.xml . 
COPY src src
RUN mvn -q -DskipTests package
FROM eclipse-temurin:21-jre
COPY --from=build /w/target/galla-api-*.jar /app.jar
USER 1000
ENTRYPOINT ["java","-XX:MaxRAMPercentage=75","-jar","/app.jar"]
