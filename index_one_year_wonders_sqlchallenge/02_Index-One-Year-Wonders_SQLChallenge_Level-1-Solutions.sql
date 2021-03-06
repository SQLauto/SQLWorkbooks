/*****************************************************************************
Copyright (c) 2020 Kendra Little
This work is licensed under a Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International License.
http://creativecommons.org/licenses/by-nc-sa/4.0/

This script is from the online course https://littlekendra.com/course/design-the-best-index-for-one-year-wonders-sqlchallenge/

Level 1 Solutions
*****************************************************************************/

/****************************************************
Level 1: design the best disk based nonclustered rowstore index 
for the given query-- in this case, "best" is defined as reducing 
the number of logical reads as much as possible for the query. 

Design only one index without using any more advanced indexing 
features such as filters, views, etc. 

Make no schema changes to the table other than 
creating the single nonclustered index.
****************************************************/

/****************************************************
Solution attempt 1:  
    Put all the predicates as keys
	Put equality (looking) columns first
	Add SELECT only columns to INCLUDES  (cover)
****************************************************/
USE BabbyNames2017;
GO

SELECT 
	FirstName, /* Include me to cover */
	FirstReportYear,
	TotalNameCount
FROM ref.FirstName
WHERE 
	FirstReportYear = LastReportYear  /* Equality predicates (ish?) */
	and TotalNameCount > 10  /* Predicate */
ORDER BY TotalNameCount DESC;
GO

CREATE INDEX ix_ref_FirstReportYear_LastReportYear_TotalNameCount_INCLUDES on 
	ref.FirstName (FirstReportYear, LastReportYear, TotalNameCount DESC)
	INCLUDE (FirstName);
GO


/* Does it use it? */
SET STATISTICS IO ON;
GO
SELECT 
	FirstName, 
	FirstReportYear,
	TotalNameCount
FROM ref.FirstName
WHERE 
	FirstReportYear = LastReportYear
	and TotalNameCount > 10
ORDER BY TotalNameCount DESC;
GO
SET STATISTICS IO ON;
GO
--Logical reads: 448

/* Why the index scan?
Look at the predicate.
*/


--Here's our index definition
--CREATE INDEX ix_ref_FirstReportYear_LastReportYear_TotalNameCount_INCLUDES on 
--	ref.FirstName (FirstReportYear, LastReportYear, TotalNameCount)
--	INCLUDE (FirstName);
--GO

--What does the data look like in this index?

--Get page numbers
--sys.dm_db_database_page_allocations is undocumented, 2012+, slow against large tables
SELECT
	pa.allocated_page_file_id,
	pa.allocated_page_page_id,
	pa.next_page_file_id,
	pa.next_page_page_id
FROM sys.indexes as si
JOIN sys.objects as so on si.object_id=so.object_id
CROSS APPLY sys.dm_db_database_page_allocations(DB_ID(), si.object_id, si.index_id, NULL, 'detailed') as pa
WHERE 
	si.name= 'ix_ref_FirstReportYear_LastReportYear_TotalNameCount_INCLUDES'
	and pa.is_allocated = 1
	and pa.page_type_desc = 'INDEX_PAGE'
	and pa.page_level = 0 /* Leaf */
ORDER BY 1;
GO


/* How seekable is this index for FirstReportYear = LastReportYear? */
/* DBCC PAGE is technically undocumented/unsupported                */
/*         Database    File# Page# DumpStyle                        */
DBCC PAGE ('BabbyNames2017', 1, 93432, 3);
GO





--Clean up
DROP INDEX ix_ref_FirstReportYear_LastReportYear_TotalNameCount_INCLUDES on 
	ref.FirstName;
GO

/****************************************************
Tweak:  
    Put all the predicates as keys
	Put the most seekable column first in the key
	Add SELECT only columns to INCLUDES 
****************************************************/

SELECT 
	FirstName, /* Include me! */
	FirstReportYear,
	TotalNameCount
FROM ref.FirstName
WHERE 
	FirstReportYear  /* Predicate */ = LastReportYear  /* Predicate */
	and TotalNameCount > 10  /* Voted Most Seekable Predicate / Miss Congeniality */
ORDER BY TotalNameCount DESC /* Hey, look at this! */;
GO


CREATE INDEX ix_ref_TotalNameCount_FirstReportYear_LastReportYear_INCLUDES on 
	ref.FirstName (TotalNameCount DESC, FirstReportYear, LastReportYear)
	INCLUDE (FirstName);
GO


/* Does it use it? */
SET STATISTICS IO ON;
GO
SELECT 
	FirstName, 
	FirstReportYear,
	TotalNameCount
FROM ref.FirstName
WHERE 
	FirstReportYear = LastReportYear
	and TotalNameCount > 10
ORDER BY TotalNameCount DESC;
GO
SET STATISTICS IO OFF;
GO
--Logical reads: 339


--Cleanup
DROP INDEX ix_ref_TotalNameCount_FirstReportYear_LastReportYear_INCLUDES on 
	ref.FirstName;
GO


/****************************************************
Solution Tweak:  
	Put the best seekable column first in the key
	Add non-seekable predicates which aren't used for ordering output to INCLUDES
	Add SELECT only columns to INCLUDES 
****************************************************/
SELECT 
	FirstName, /* Include me! */
	FirstReportYear,
	TotalNameCount
FROM ref.FirstName
WHERE 
	FirstReportYear = LastReportYear  /* Non-seekable Predicates */
	and TotalNameCount > 10  /* Most Seekable Predicate */
ORDER BY TotalNameCount DESC /* ORDER BY column */;
GO



CREATE INDEX ix_ref_TotalNameCount_INCLUDES on 
	ref.FirstName (TotalNameCount DESC)
	INCLUDE (FirstName, FirstReportYear, LastReportYear);
GO

/* Does it use it? */
SET STATISTICS IO ON;
GO
SELECT 
	FirstName, 
	FirstReportYear,
	TotalNameCount
FROM ref.FirstName
WHERE 
	FirstReportYear = LastReportYear
	and TotalNameCount > 10
ORDER BY TotalNameCount DESC;
GO
SET STATISTICS IO OFF;
GO
--Logical reads: 338


DROP INDEX ix_ref_TotalNameCount_INCLUDES on 
	ref.FirstName;
GO




/****************************************************
Solution Tweak:  
    We're measuring by logical reads so...
    Let's compress it!
    😃 😃 😃 😃 😃 😃 😃 😃 😃 😃 😃
****************************************************/


CREATE INDEX ix_ref_TotalNameCount_INCLUDES on 
	ref.FirstName (TotalNameCount DESC)
	INCLUDE (FirstName, FirstReportYear, LastReportYear)
    WITH (DATA_COMPRESSION = PAGE);
GO


SET STATISTICS IO ON;
GO
SELECT 
	FirstName, 
	FirstReportYear,
	TotalNameCount
FROM ref.FirstName
WHERE 
	FirstReportYear = LastReportYear
	and TotalNameCount > 10
ORDER BY TotalNameCount DESC;
GO
SET STATISTICS IO OFF;
GO
--Logical reads: 183



--Cleanup Redux
DROP INDEX IF EXISTS 
    ix_ref_FirstReportYear_LastReportYear_TotalNameCount_INCLUDES on ref.FirstName,
    ix_ref_TotalNameCount_FirstReportYear_LastReportYear_INCLUDES on ref.FirstName,
    ix_ref_TotalNameCount_INCLUDES on ref.FirstName;
GO

