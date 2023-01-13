
<p align="justify">


## Background

Official data on commuting and migration flows in England and Wales have historically been reported for local authority districts (LAD) among other spatial classifications. Observing flows between the same two LAD over time is often complicated by the following:

- Administrative boundary changes
- Changes in the code associated with a given LAD
- The reporting of commuting flows for Census Merged LAD  in the 2011 UK Census (CMLAD11)

## Output data
- `./output/lad_lad20x.csv` contains a correspondence table matching all English and Welsh LAD codes that were live between 2001 and 2020 to a harmonised LAD (LAD20X) equivalent or parent. The table can be used to harmonise data within and between the following sources:

  - 1991, 2001, and 2011 Census flow data published on the [UK Data Service WICID database](https://wicid.ukdataservice.ac.uk) that are reported for 2001 Interaction Data Districts or CMLAD11
  - Any data published on the [Office for National Statistics (ONS) website](https://www.ons.gov.uk) or the [ONS Nomis database](https://www.nomisweb.co.uk) that are reported for LAD versions that were live between 2001 and 2020 or CMLAD11

- `./output/tables.RDS` contains a list of auxiliary correspondence tables.

- `./output/geometries/lad20x.shp` contains LAD20X boundary data.

- `./output/lad20x.png` contains a map of LAD20X boundaries.

## Method

The R script `get_tables.R` produces the correspondence table in the following steps:

1. Using the ONS Code History Database, identify cases where there are one-to-many matches between successive LAD code versions (i.e. due to boundary changes). If the predecessor code has the same assigned name as one of its successor codes, update the database by dropping matches to the other successor codes.
   > **Note:** *All identified one-to-many matches are caused by three boundary changes with each being very minor and primarily concerning non-   residential areas. As such, in all cases, there is a successor area that is effectively identical to the predecessor area with which it also shares the same name. The boundary changes concerned are detailed in [Legislation.gov.uk](https://legislation.gov.uk) where they are searchable using the IDs and names of the relevant statutory instruments. The latter can be viewed in R as follows:*
    ```
      library(dplyr)
      
      tables <- readRDS("./output/tables.RDS")
      
      tables[["LAD-LAD_P n-1"]] %>%
       filter(flag == "drop") %>%
       select(SI_ID, SI_TITLE)
    ```

2. Using the updated ONS Code History Database, which now only contains one-to-one and many-to-one matches between successive LAD code versions,  produce a correspondence table matching all terminated codes to their live successor.
    > **Note:** *Given that the December 2020 version of the database is used, the live codes constitute the 2020 version of the LAD classification (LAD20).*

3. Using boundary data and a spatial join, identify many-to-one matches between LAD20 and CMLAD11. In the correspondence table, replace the codes and names of the affected LAD20 with those of the parent CMLAD11. The resulting classification, which is comprised of **364 LAD20** and **two CMLAD11** covering the whole of England and Wales,  is the harmonised LAD classification (LAD20X).
   > **Note:** *The two CMLAD11 are E41000052 (Cornwall and Isles of Scilly) and E41000324 (Westminster and City of London).*
   

## Input data
 - `./rawdata/ONS - Code History Database (Dec 2020 v2).zip` contains the second version of the ONS Code History Database as of December 2020, downloaded from the [ONS Open Geography Portal](https://hub.arcgis.com/datasets/ons::code-history-database-december-2020-for-the-united-kingdom-version-2-1/about).      
 - `./rawdata/geometries/ONS - CLMLAD 2011 boundaries.zip` contains 2011 Census Merged LAD boundaries, downloaded from the [ONS Open Geography Portal](https://opendata.arcgis.com/api/v3/datasets/42a6cfa42e6d4070bfdf2e403bb68265_0/downloads/data?format=shp&spatialRefId=27700&where=1%3D1).
 - `./rawdata/geometries/ONS - LAD (Dec 2020) boundaries.zip` contains LAD boundaries as of Decmber 2020, downloaded from the [ONS Open Geography Portal](https://opendata.arcgis.com/api/v3/datasets/0c94ff9e45a84f20b380875869e06e5f_0/downloads/data?format=shp&spatialRefId=27700&where=1%3D1).

## Attribution statements
- Contains public sector information licensed under the Open Government Licence v3.0.
- Contains Ordnance Survey (OS) data © Crown copyright and database right 2022.

</p>
