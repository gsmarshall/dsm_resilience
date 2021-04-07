/*
Hannah Rigdon and Sam Marshall
Open Source GIS Lab 04
31 March 2021
*/


/*STEP 1: DISSOLVE THE FLOOD GEOMETRIES */
CREATE TABLE lab_floodsimple
AS
SELECT st_union(geom)::geometry(multipolygon, 32737) as geom
FROM flood;

/*STEP 2: Calculate ward area */
ALTER TABLE wards
ADD COLUMN areakm2 real

UPDATE wards
SET areakm2 = st_area(geom) /1000000

/*STEP 3: intersect wards w floods to make simpler geometries/subgeometries */
SELECT wards.*, st_multi(st_intersection(wards.geom, lab_floodsimple.geom))::geometry(multipolygon,32737) as geom
FROM wards INNER JOIN lab_floodsimple
ON st_intersects(wards.geom, lab_floodsimple.geom);

/*STEP 4: Time to clean up our buildings data. we are defining buildings based on */
SELECT *
FROM planet_osm_polygon
WHERE  building is not null;

/* STEP 5: Buffer the roads */
CREATE TABLE lab_roads_buffered AS SELECT*, st_buffer(way::geography, 10)::geometry(polygon,4326) as geom
FROM planet_osm_roads

ALTER TABLE lab_roads_buffered
DROP COLUMN geom;

-- clip the roads to the wards
CREATE TABLE lab_roads_clipped
AS
SELECT lab_roads_buffered.*, st_multi(st_intersection(lab_roads_buffered.geom, wards.geom))::geometry(multipolygon, 4326) as geom01
FROM lab_roads_buffered INNER JOIN wards
ON st_intersects(lab_roads_buffered.geom, wards.geom);


-- sort out just buildings from the polygon dataset
CREATE TABLE lab_buildings
AS
SELECT*
FROM planet_osm_polygon
WHERE  building is not null;

-- union impervious surfaces together
CREATE TABLE lab_impervious_surfaces
AS
SELECT st_multi(st_union(lab_roads_clipped.geom01, lab_buildings.way))::geometry(multipolygon, 4326) as geom02
FROM lab_roads_clipped, lab_buildings

-- delete duplicate GEOMETRIES

CREATE TABLE lab_impervious_noDups
AS
SELECT (st_dump(geom)).geom::geometry(polygon, 4326)
FROM lab_impervious_surfaces;
