# LOAD PACKAGES ----------------------------------------------------------------

packages <-
  c(
    "dplyr",
    "readr",
    "readxl",
    "ggplot2",
    "sf"
  )

for (p in packages){ 
  if (! (p %in% installed.packages())){
    install.packages(p)
  }
}

library(dplyr)
library(ggplot2)

# CONSTRUCT GEOGRAPHICAL LOOK-UP TABLES ----------------------------------------

geolkp <- list()

# ******************************************************************************
# Construct LAD (Dec 2020) to LAD (previous) lookup
# ******************************************************************************

# Import geography code/name change lookup from CHD
geolkp[["LAD-LAD_P"]][[1]] <- 
  readr::read_csv(
    unz("./rawdata/ONS - Code History Database (Dec 2020 v2).zip", "Changes_V2.csv"),
    col_types = readr::cols(.default = "c")
  ) 

# Import geography code/name attributes from CHD
geolkp[["LAD-LAD_P"]][[2]] <-
  readr::read_csv(
    unz("./rawdata/ONS - Code History Database (Dec 2020 v2).zip", "ChangeHistory_V2.csv"),
    col_types = readr::cols(.default = "c")
  )

# Keep only LAD codes/names and append status column to lookup
geolkp[["LAD-LAD_P"]][[1]] <- 
  geolkp[["LAD-LAD_P"]][[1]]  %>%
  select(-GEOGNMW, -GEOGNMW_P) %>%
  filter(grepl('E06|E07|E08|E09|W06', GEOGCD)) 

geolkp[["LAD-LAD_P"]] <- 
  left_join(
    geolkp[["LAD-LAD_P"]][[1]],
    geolkp[["LAD-LAD_P"]][[2]][,c("GEOGCD", "GEOGNM", "STATUS")],
    by = c("GEOGCD", "GEOGNM")
  ) %>%
  rename(
    LADCD = GEOGCD,
    LADNM = GEOGNM,
    LADCD_P = GEOGCD_P,
    LADNM_P = GEOGNM_P
  ) %>%
  distinct()

# Identify n-to-1 changes; for boundary changes, flag secondary succeeding areas
geolkp[["LAD-LAD_P n-1"]] <- 
  geolkp[["LAD-LAD_P"]] %>%
  group_by(LADCD_P) %>%
  filter(n()>1) %>%
  mutate(
    flag = case_when(
      (LADNM != LADNM_P) & !grepl("Name|re-coding", SI_TITLE) ~ "drop"
    )
  ) %>%
  ungroup()

# Derive columns for corresponding LAD code/names as of Dec 2020:
# (a) n-to-1 boundary changes are restricted to the primary succeeding area
geolkp[["LAD20-LAD"]] <- 
  geolkp[["LAD-LAD_P"]] %>%
  left_join(geolkp[["LAD-LAD_P n-1"]]) %>% 
  filter(is.na(flag)) 

# (b) Codes/names appearing in 'previous' columns are matched to live equivs
# (c) Live codes/names are the Dec 2020 LAD version and are set as such
geolkp[["LAD20-LAD"]] <-
  geolkp[["LAD20-LAD"]] %>%
  left_join( 
    .[.$STATUS == "live", c("LADCD", "LADCD_P", "LADNM", "LADNM_P")], 
    by = c("LADCD" = "LADCD_P", "LADNM" = "LADNM_P")
  ) %>%
  rename(LAD20CD = LADCD.y, LAD20NM = LADNM.y) %>%
  mutate( 
    LAD20CD = case_when(STATUS == "live" ~ LADCD, TRUE ~ LAD20CD),
    LAD20NM = case_when(STATUS == "live" ~ LADNM, TRUE ~ LAD20NM)
  ) 

# (d) NAs due to >1 changes over lifetime are matched to successors' LAD20
geolkp[["LAD20-LAD"]] <-
  geolkp[["LAD20-LAD"]] %>%
  left_join( # 1st iteration
    geolkp[["LAD20-LAD"]][,c("LADCD_P", "LAD20CD", "LADNM_P", "LAD20NM")], 
    by = c("LADCD" = "LADCD_P" , "LADNM" = "LADNM_P")
  ) %>%
  mutate(
    LAD20CD.x = case_when(is.na(LAD20CD.x) ~ LAD20CD.y, TRUE ~ LAD20CD.x),
    LAD20NM.x = case_when(is.na(LAD20NM.x) ~ LAD20NM.y, TRUE ~ LAD20NM.x)
  ) %>%
  select(-LAD20CD.y, -LAD20NM.y) %>%
  rename(LAD20CD = LAD20CD.x, LAD20NM = LAD20NM.x) 

# Finalise LAD20-LAD code lookup by stacking LAD and LAD_P columns
geolkp[["LAD20-LAD"]] <-
  geolkp[["LAD20-LAD"]] %>%
  select(LADCD, LADCD_P, LAD20CD, LAD20NM)

geolkp[["LAD20-LAD"]] <-
  as_tibble(
    data.frame(
      geolkp[["LAD20-LAD"]][3:4], 
      stack(geolkp[["LAD20-LAD"]][1:2])
    )
  )

geolkp[["LAD20-LAD"]] <-
  geolkp[["LAD20-LAD"]] %>%
  rename(LADCD = values) %>%
  select(-ind) %>%
  distinct() %>%
  select(LAD20CD, LAD20NM, LADCD) %>% 
  filter(!is.na(LAD20CD)) 

# Add equivalent codes
equivs <- 
  readr::read_csv(
    unz("./rawdata/ONS - Code History Database (Dec 2020 v2).zip", "Equivalents_V2.csv"),
    col_types = readr::cols(.default = "c")
  ) %>% 
  filter(grepl('E06|E07|E08|E09|W06', GEOGCD), grepl("live", STATUS)) %>%
  select(GEOGCD, GEOGNM, GEOGCDO) %>% 
  rename(LAD20CD = GEOGCD, LAD20NM = GEOGNM, LADCD = GEOGCDO) %>%
  distinct()

geolkp[["LAD20-LAD with equivs"]] <- 
  rbind(geolkp[["LAD20-LAD"]], equivs) %>% 
  distinct()


# ******************************************************************************
# Construct LAD (Dec 2020) to CMLAD2011 lookup 
# ******************************************************************************

# Read LAD20 and CMLAD11 boundaries; convert to OS CRS
temp <- tempfile()
unzip("./rawdata/geometries/ONS - LAD (Dec 2020) boundaries.zip", exdir = temp)
lad20_sf <- 
  sf::st_read(temp) %>% 
  sf::st_transform(27700) %>%
  select(LAD20CD, LAD20NM, geometry) %>%
  filter(grepl("^E|^W", LAD20CD)) # only Keep England/Wales

temp <- tempfile()
unzip("./rawdata/geometries//ONS - CMLAD 2011 boundaries.zip", exdir = temp)
cmlad11_sf <- 
  sf::st_read(temp) %>% 
  sf::st_transform(27700) %>%
  select(cmlad11cd, cmlad11nm, geometry) 

# Construct LAD20-CMLAD11 lookup by point-in-polygon; identify n-to-1 cases
geolkp[["LAD20-CMLAD11 EW"]] <-
  sf::st_join(
    sf::st_point_on_surface(lad20_sf), cmlad11_sf
  ) %>%
  sf::st_drop_geometry()

geolkp[["LAD20-CMLAD11 EW n-1"]] <- geolkp[["LAD20-CMLAD11 EW"]] %>%
  group_by(cmlad11cd) %>%
  filter(n()>1) %>%
  ungroup()

# ******************************************************************************
# Construct LAD20X to LAD lookup
#
# Notes: 
# LAD20X is equal to LAD20 except where there are n-to-1 matches with CMLAD11,
# in which case LAD20 is replaced with CMLAD11.
# ******************************************************************************

geolkp[["LAD20X-LAD"]] <- geolkp[["LAD20-LAD with equivs"]] %>%
  left_join(geolkp[["LAD20-CMLAD11 EW n-1"]], by = c("LAD20CD", "LAD20NM")) %>%
  mutate(
    LAD20CD = case_when(!is.na(cmlad11cd) ~ cmlad11cd, TRUE ~ LAD20CD),
    LAD20NM = case_when(!is.na(cmlad11nm) ~ cmlad11nm, TRUE ~ LAD20NM)
  ) %>%
  rename(LAD20XCD = LAD20CD, LAD20XNM = LAD20NM) %>%
  select(LAD20XCD, LAD20XNM, LADCD)

# Add n-1 LAD20XCD to LADCD
geolkp[["LAD20X-LAD"]] <- rbind(
  geolkp[["LAD20X-LAD"]],
  geolkp[["LAD20-CMLAD11 EW n-1"]] %>% 
    select(cmlad11cd, cmlad11nm) %>%
    rename(LAD20XCD = cmlad11cd, LAD20XNM = cmlad11nm) %>%
    mutate(LADCD = LAD20XCD) %>%
    distinct()
)


# PREPARE  BOUNDARY OUTPUT -----------------------------------------------------

lad20x_sf <-
  lad20_sf %>%
  sf::st_buffer(dist = 0.001) %>%
  left_join(geolkp[["LAD20X-LAD"]], by = c("LAD20CD" = "LADCD")) %>%
  group_by(LAD20XCD, LAD20XNM) %>%
  summarise(
    geometry = sf::st_union(geometry)
  ) %>%
  ungroup()

ggplot() +
  geom_sf(
    data = lad20x_sf,
    color = "white",
    size =.2
  ) +
  theme_void() 

ggsave(filename = "./output/lad20x.png", height=8, width=4.5, device='png', dpi=700)

# SAVE OUTPUT & CLEAN UP ENVIRONMENT -------------------------------------------

saveRDS(geolkp, file="./output/tables.RDS") 
write.csv(geolkp[["LAD20X-LAD"]] , file="./output/lad_lad20x.csv", row.names = FALSE)
sf::write_sf(lad20x_sf, dsn="./output/geometries/lad20x.shp")

rm(list = ls())
gc()



