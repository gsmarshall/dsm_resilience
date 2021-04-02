/*
Hannah Rigdon and Sam Marshall
Open Source GIS Lab 04
31 March 2021
*/

CREATE TABLE flooddissolve
AS
SELECT st_union(geom)::geometry(multipolygon, 32737) as geom
FROM flood;
