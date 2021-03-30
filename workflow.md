#### General Question: Determine land cover in floodplains in Dar es Salaam, using the area of buildings and roads as a proxy
**More Specifically: calculate the percent area covered by impervious surfaces within flood prone and non flood prone areas of each ward**


### Data
- flood scenarios layer (either 'flood' layer in public schema or Dar es Salaam Flood Scenario from resilience academy)
- OSM building footprints (planet_osm_polygons) and roads (planet_osm_roads)

### Initial Notes
- Definitions: 
  - an area is flood-prone if it is covered by any part of the flood scenarios layer - i.e. has any probable flood depth


### Questions
- how do we clean and filter the building data? looks like there are some crazy big polygons with the tag 'building' = 'yes' that are certainly not single buildings...can we effectively remove those?



workflow:
1. create impervious surfaces layer
  - calculate area of each feature (sqkm)
  - calculate area of floodplain in each ward

2. intersect with floodplains
  - group by ward

3. summarize percent impervious area compared to total area
