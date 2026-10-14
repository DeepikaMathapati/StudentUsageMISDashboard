/*
StudentUsageMISDB synthetic demo seed, version 1.
Review and run manually in SSMS. This file has not been executed by Codex.

All names and codes are fictional. No personal information is generated.
UsageSeconds is measured in SECONDS for THIS DEMO DATA ONLY. This convention
is not an independently verified fact about a production system.

Expected additions: 3 districts, 6 blocks, 12 clusters, 24 schools,
480 students (384 active, 96 inactive), and 6,912 usage rows.
Per school: active positions 1-2 have zero usage; positions 3-10 have
21 rows each; positions 11-16 have 20 rows each. Inactive positions 17-20
have no usage. Each usage type has exactly 1,152 rows across the dataset.

Ownership namespace: DEMO-MIS-202609-V1. Reserve this prefix for this seed.
Schema changes and ownership tables are deliberately avoided. A complete
matching seed is validated and skipped on rerun. A partial/changed dataset
or namespace collision fails closed; nothing is repaired, deleted, or overwritten.
An unrelated record that perfectly reproduces this entire dataset cannot be
distinguished without an ownership schema; review the reserved namespace first.
*/
USE [StudentUsageMISDB];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @Prefix nvarchar(30) = N'DEMO-MIS-202609-V1';
DECLARE @StartDate date = DATEFROMPARTS(2026, 9, 1);
DECLARE @LockResult int;
DECLARE @AlreadyPresent bit = 0;

-- These table variables describe expected data; they are not database objects.
DECLARE @Numbers TABLE (N int PRIMARY KEY);
DECLARE @Districts TABLE (Ordinal int PRIMARY KEY, DistrictName nvarchar(100));
DECLARE @Blocks TABLE (Ordinal int PRIMARY KEY, DistrictOrdinal int, BlockName nvarchar(100));
DECLARE @Clusters TABLE (Ordinal int PRIMARY KEY, BlockOrdinal int, ClusterName nvarchar(100));
DECLARE @Schools TABLE (Ordinal int PRIMARY KEY, ClusterOrdinal int,
    SchoolCode nvarchar(30), SchoolName nvarchar(150));
DECLARE @Students TABLE (Ordinal int PRIMARY KEY, SchoolOrdinal int,
    PositionInSchool int, StudentCode nvarchar(30), IsActive bit);
DECLARE @Types TABLE (Ordinal int PRIMARY KEY, UsageType nvarchar(30), BaseSeconds int);
DECLARE @Usage TABLE (StudentOrdinal int, UsageDate date,
    UsageType nvarchar(30), UsageSeconds decimal(18,2));
DECLARE @DistrictMap TABLE (Ordinal int PRIMARY KEY, DistrictId int);
DECLARE @BlockMap TABLE (Ordinal int PRIMARY KEY, BlockId int);
DECLARE @ClusterMap TABLE (Ordinal int PRIMARY KEY, ClusterId int);
DECLARE @SchoolMap TABLE (Ordinal int PRIMARY KEY, SchoolId int);
DECLARE @StudentMap TABLE (Ordinal int PRIMARY KEY, StudentId int);

BEGIN TRY
    BEGIN TRANSACTION;
    -- Serialize executions of this seed. HOLDLOCK also protects inspected
    -- namespace ranges against concurrent inserts until this transaction ends.
    EXEC @LockResult = sys.sp_getapplock
        @Resource = N'StudentUsageMISDB:DEMO-MIS-202609-V1',
        @LockMode = N'Exclusive', @LockOwner = N'Transaction', @LockTimeout = 10000;
    IF @LockResult < 0
        THROW 51000, 'Could not acquire the demo seed lock. No data was changed.', 1;

    ;WITH Digits AS (
        SELECT N FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) d(N)
    )
    INSERT INTO @Numbers (N)
    SELECT 1 + a.N + 10*b.N + 100*c.N
    FROM Digits a CROSS JOIN Digits b CROSS JOIN Digits c
    WHERE a.N + 10*b.N + 100*c.N < 480;

    INSERT INTO @Districts
    SELECT N, @Prefix + N' District ' + CASE N WHEN 1 THEN N'Alpha'
        WHEN 2 THEN N'Beta' ELSE N'Gamma' END FROM @Numbers WHERE N <= 3;
    INSERT INTO @Blocks
    SELECT N, (N-1)/2+1, @Prefix + N' Block ' + RIGHT(N'00'+CONVERT(nvarchar(2),N),2)
    FROM @Numbers WHERE N <= 6;
    INSERT INTO @Clusters
    SELECT N, (N-1)/2+1, @Prefix + N' Cluster ' + RIGHT(N'00'+CONVERT(nvarchar(2),N),2)
    FROM @Numbers WHERE N <= 12;
    INSERT INTO @Schools
    SELECT N, (N-1)/2+1, @Prefix + N'-S' + RIGHT(N'000'+CONVERT(nvarchar(3),N),3),
        @Prefix + N' Fictional School ' + RIGHT(N'00'+CONVERT(nvarchar(2),N),2)
    FROM @Numbers WHERE N <= 24;
    INSERT INTO @Students
    SELECT N, (N-1)/20+1, (N-1)%20+1,
        @Prefix + N'-T' + RIGHT(N'0000'+CONVERT(nvarchar(4),N),4),
        CONVERT(bit, CASE WHEN (N-1)%20+1 <= 16 THEN 1 ELSE 0 END)
    FROM @Numbers;
    INSERT INTO @Types VALUES
        (1,N'Video',300), (2,N'Activity',120), (3,N'Surfing',60),
        (4,N'PDF',90), (5,N'Assessment',600), (6,N'Offline',180);

    -- Consecutive type offsets within each school distribute 288 rows evenly
    -- across the six types. Every participating student receives all six types.
    INSERT INTO @Usage
    SELECT s.Ordinal,
        DATEADD(day, (s.Ordinal*11 + n.N*7)%30, @StartDate), t.UsageType,
        CONVERT(decimal(18,2), CASE WHEN (s.Ordinal+n.N)%97=0 THEN 0
            ELSE t.BaseSeconds + (s.Ordinal*37+n.N*53)%900
                + ((s.Ordinal+n.N)%100)/100.0 END)
    FROM @Students s
    JOIN @Numbers n ON n.N <= CASE WHEN s.PositionInSchool <= 10 THEN 21 ELSE 20 END
    CROSS APPLY (SELECT CASE WHEN s.PositionInSchool <= 10
        THEN (s.PositionInSchool-3)*21 ELSE 168+(s.PositionInSchool-11)*20 END AS TypeOffset) o
    JOIN @Types t ON t.Ordinal = (o.TypeOffset+n.N-1)%6+1
    WHERE s.IsActive=1 AND s.PositionInSchool BETWEEN 3 AND 16;

    IF (SELECT COUNT(*) FROM @Usage) <> 6912
        THROW 51001, 'Unexpected generated usage count. No data was changed.', 1;

    IF EXISTS (SELECT 1 FROM dbo.Districts WITH (UPDLOCK,HOLDLOCK)
        WHERE LEFT(DistrictName,LEN(@Prefix))=@Prefix)
        OR EXISTS (SELECT 1 FROM dbo.Blocks WITH (UPDLOCK,HOLDLOCK)
        WHERE LEFT(BlockName,LEN(@Prefix))=@Prefix)
        OR EXISTS (SELECT 1 FROM dbo.Clusters WITH (UPDLOCK,HOLDLOCK)
        WHERE LEFT(ClusterName,LEN(@Prefix))=@Prefix)
        OR EXISTS (SELECT 1 FROM dbo.Schools WITH (UPDLOCK,HOLDLOCK)
        WHERE LEFT(SchoolCode,LEN(@Prefix))=@Prefix OR LEFT(SchoolName,LEN(@Prefix))=@Prefix)
        OR EXISTS (SELECT 1 FROM dbo.Students WITH (UPDLOCK,HOLDLOCK)
        WHERE LEFT(StudentCode,LEN(@Prefix))=@Prefix)
        SET @AlreadyPresent=1;

    IF @AlreadyPresent=0
        INSERT INTO dbo.Districts (DistrictName) SELECT DistrictName FROM @Districts;
    INSERT INTO @DistrictMap
    SELECT e.Ordinal, a.DistrictId FROM @Districts e
    JOIN dbo.Districts a ON a.DistrictName=e.DistrictName;

    IF @AlreadyPresent=0
        INSERT INTO dbo.Blocks (DistrictId,BlockName)
        SELECT m.DistrictId,e.BlockName FROM @Blocks e
        JOIN @DistrictMap m ON m.Ordinal=e.DistrictOrdinal;
    INSERT INTO @BlockMap
    SELECT e.Ordinal,a.BlockId FROM @Blocks e JOIN dbo.Blocks a ON a.BlockName=e.BlockName;

    IF @AlreadyPresent=0
        INSERT INTO dbo.Clusters (BlockId,ClusterName)
        SELECT m.BlockId,e.ClusterName FROM @Clusters e
        JOIN @BlockMap m ON m.Ordinal=e.BlockOrdinal;
    INSERT INTO @ClusterMap
    SELECT e.Ordinal,a.ClusterId FROM @Clusters e JOIN dbo.Clusters a ON a.ClusterName=e.ClusterName;

    IF @AlreadyPresent=0
        INSERT INTO dbo.Schools (ClusterId,SchoolCode,SchoolName)
        SELECT m.ClusterId,e.SchoolCode,e.SchoolName FROM @Schools e
        JOIN @ClusterMap m ON m.Ordinal=e.ClusterOrdinal;
    INSERT INTO @SchoolMap
    SELECT e.Ordinal,a.SchoolId FROM @Schools e JOIN dbo.Schools a ON a.SchoolCode=e.SchoolCode;

    IF @AlreadyPresent=0
        INSERT INTO dbo.Students (SchoolId,StudentCode,IsActive)
        SELECT m.SchoolId,e.StudentCode,e.IsActive FROM @Students e
        JOIN @SchoolMap m ON m.Ordinal=e.SchoolOrdinal;
    INSERT INTO @StudentMap
    SELECT e.Ordinal,a.StudentId FROM @Students e JOIN dbo.Students a ON a.StudentCode=e.StudentCode;

    IF @AlreadyPresent=0
        INSERT INTO dbo.StudentUsage (StudentId,UsageDate,UsageType,UsageSeconds)
        SELECT m.StudentId,e.UsageDate,e.UsageType,e.UsageSeconds FROM @Usage e
        JOIN @StudentMap m ON m.Ordinal=e.StudentOrdinal;

    -- Verify counts and exact values, including foreign-key parent IDs.
    -- EXCEPT in both directions detects missing, changed, and unexpected rows.
    IF (SELECT COUNT(*) FROM dbo.Districts WHERE LEFT(DistrictName,LEN(@Prefix))=@Prefix)<>3
        OR (SELECT COUNT(*) FROM dbo.Blocks WHERE LEFT(BlockName,LEN(@Prefix))=@Prefix)<>6
        OR (SELECT COUNT(*) FROM dbo.Clusters WHERE LEFT(ClusterName,LEN(@Prefix))=@Prefix)<>12
        OR (SELECT COUNT(*) FROM dbo.Schools WHERE LEFT(SchoolCode,LEN(@Prefix))=@Prefix
            OR LEFT(SchoolName,LEN(@Prefix))=@Prefix)<>24
        OR (SELECT COUNT(*) FROM dbo.Students WHERE LEFT(StudentCode,LEN(@Prefix))=@Prefix)<>480
        OR (SELECT COUNT(*) FROM @DistrictMap)<>3 OR (SELECT COUNT(*) FROM @BlockMap)<>6
        OR (SELECT COUNT(*) FROM @ClusterMap)<>12 OR (SELECT COUNT(*) FROM @SchoolMap)<>24
        OR (SELECT COUNT(*) FROM @StudentMap)<>480
        THROW 51002, 'Demo namespace is incomplete or conflicts with existing data. No changes committed.', 1;

    IF EXISTS (SELECT a.BlockName,a.DistrictId FROM dbo.Blocks a WHERE LEFT(a.BlockName,LEN(@Prefix))=@Prefix
        EXCEPT SELECT e.BlockName,m.DistrictId FROM @Blocks e JOIN @DistrictMap m ON m.Ordinal=e.DistrictOrdinal)
        OR EXISTS (SELECT e.BlockName,m.DistrictId FROM @Blocks e JOIN @DistrictMap m ON m.Ordinal=e.DistrictOrdinal
        EXCEPT SELECT a.BlockName,a.DistrictId FROM dbo.Blocks a WHERE LEFT(a.BlockName,LEN(@Prefix))=@Prefix)
        OR EXISTS (SELECT a.ClusterName,a.BlockId FROM dbo.Clusters a WHERE LEFT(a.ClusterName,LEN(@Prefix))=@Prefix
        EXCEPT SELECT e.ClusterName,m.BlockId FROM @Clusters e JOIN @BlockMap m ON m.Ordinal=e.BlockOrdinal)
        OR EXISTS (SELECT e.ClusterName,m.BlockId FROM @Clusters e JOIN @BlockMap m ON m.Ordinal=e.BlockOrdinal
        EXCEPT SELECT a.ClusterName,a.BlockId FROM dbo.Clusters a WHERE LEFT(a.ClusterName,LEN(@Prefix))=@Prefix)
        OR EXISTS (SELECT a.SchoolCode,a.SchoolName,a.ClusterId FROM dbo.Schools a
        WHERE LEFT(a.SchoolCode,LEN(@Prefix))=@Prefix OR LEFT(a.SchoolName,LEN(@Prefix))=@Prefix
        EXCEPT SELECT e.SchoolCode,e.SchoolName,m.ClusterId FROM @Schools e JOIN @ClusterMap m ON m.Ordinal=e.ClusterOrdinal)
        OR EXISTS (SELECT e.SchoolCode,e.SchoolName,m.ClusterId FROM @Schools e JOIN @ClusterMap m ON m.Ordinal=e.ClusterOrdinal
        EXCEPT SELECT a.SchoolCode,a.SchoolName,a.ClusterId FROM dbo.Schools a
        WHERE LEFT(a.SchoolCode,LEN(@Prefix))=@Prefix OR LEFT(a.SchoolName,LEN(@Prefix))=@Prefix)
        OR EXISTS (SELECT a.StudentCode,a.SchoolId,a.IsActive FROM dbo.Students a WHERE LEFT(a.StudentCode,LEN(@Prefix))=@Prefix
        EXCEPT SELECT e.StudentCode,m.SchoolId,e.IsActive FROM @Students e JOIN @SchoolMap m ON m.Ordinal=e.SchoolOrdinal)
        OR EXISTS (SELECT e.StudentCode,m.SchoolId,e.IsActive FROM @Students e JOIN @SchoolMap m ON m.Ordinal=e.SchoolOrdinal
        EXCEPT SELECT a.StudentCode,a.SchoolId,a.IsActive FROM dbo.Students a WHERE LEFT(a.StudentCode,LEN(@Prefix))=@Prefix)
        THROW 51003, 'Demo values or relationships differ from this seed. No changes committed.', 1;

    -- Compare grouped usage multiplicities as well as values to detect duplicates.
    IF EXISTS (
        SELECT a.StudentId,a.UsageDate,a.UsageType,a.UsageSeconds,COUNT_BIG(*) AS Copies
        FROM dbo.StudentUsage a JOIN dbo.Students s ON s.StudentId=a.StudentId
        WHERE LEFT(s.StudentCode,LEN(@Prefix))=@Prefix
        GROUP BY a.StudentId,a.UsageDate,a.UsageType,a.UsageSeconds
        EXCEPT
        SELECT m.StudentId,e.UsageDate,e.UsageType,e.UsageSeconds,COUNT_BIG(*)
        FROM @Usage e JOIN @StudentMap m ON m.Ordinal=e.StudentOrdinal
        GROUP BY m.StudentId,e.UsageDate,e.UsageType,e.UsageSeconds)
        OR EXISTS (
        SELECT m.StudentId,e.UsageDate,e.UsageType,e.UsageSeconds,COUNT_BIG(*)
        FROM @Usage e JOIN @StudentMap m ON m.Ordinal=e.StudentOrdinal
        GROUP BY m.StudentId,e.UsageDate,e.UsageType,e.UsageSeconds
        EXCEPT
        SELECT a.StudentId,a.UsageDate,a.UsageType,a.UsageSeconds,COUNT_BIG(*)
        FROM dbo.StudentUsage a JOIN dbo.Students s ON s.StudentId=a.StudentId
        WHERE LEFT(s.StudentCode,LEN(@Prefix))=@Prefix
        GROUP BY a.StudentId,a.UsageDate,a.UsageType,a.UsageSeconds)
        THROW 51004, 'Demo usage is incomplete, changed, or duplicated. No changes committed.', 1;

    COMMIT TRANSACTION;
    PRINT CASE WHEN @AlreadyPresent=1 THEN 'Complete matching demo dataset verified; no rows inserted.'
        ELSE 'Demo dataset inserted and validated successfully.' END;
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO

/* READ-ONLY VERIFICATION: run separately after a successful manual seed.
Counts below are scoped to the demo namespace, so unrelated records are excluded.
*/
DECLARE @Prefix nvarchar(30)=N'DEMO-MIS-202609-V1';
SELECT N'Districts' AS TableName,COUNT_BIG(*) AS [RowCount],3 AS Expected
FROM dbo.Districts WHERE LEFT(DistrictName,LEN(@Prefix))=@Prefix
UNION ALL SELECT N'Blocks',COUNT_BIG(*),6 FROM dbo.Blocks WHERE LEFT(BlockName,LEN(@Prefix))=@Prefix
UNION ALL SELECT N'Clusters',COUNT_BIG(*),12 FROM dbo.Clusters WHERE LEFT(ClusterName,LEN(@Prefix))=@Prefix
UNION ALL SELECT N'Schools',COUNT_BIG(*),24 FROM dbo.Schools
WHERE LEFT(SchoolCode,LEN(@Prefix))=@Prefix OR LEFT(SchoolName,LEN(@Prefix))=@Prefix
UNION ALL SELECT N'Students',COUNT_BIG(*),480 FROM dbo.Students WHERE LEFT(StudentCode,LEN(@Prefix))=@Prefix
UNION ALL SELECT N'StudentUsage',COUNT_BIG(*),6912 FROM dbo.StudentUsage u
JOIN dbo.Students s ON s.StudentId=u.StudentId WHERE LEFT(s.StudentCode,LEN(@Prefix))=@Prefix;

-- Expected: each school has 20 students, 16 active and 4 inactive.
SELECT sc.SchoolCode,COUNT(s.StudentId) AS Students,
    SUM(CASE WHEN s.IsActive=1 THEN 1 ELSE 0 END) AS ActiveStudents,
    SUM(CASE WHEN s.IsActive=0 THEN 1 ELSE 0 END) AS InactiveStudents
FROM dbo.Schools sc LEFT JOIN dbo.Students s ON s.SchoolId=sc.SchoolId
WHERE LEFT(sc.SchoolCode,LEN(@Prefix))=@Prefix GROUP BY sc.SchoolCode ORDER BY sc.SchoolCode;

-- Expected: 48 active with zero rows, 144 active with 20, 192 active with 21;
-- 96 inactive with zero. There must be no inactive students with usage.
;WITH StudentCounts AS (
    SELECT s.StudentId,s.IsActive,COUNT(u.UsageId) AS UsageRows
    FROM dbo.Students s LEFT JOIN dbo.StudentUsage u ON u.StudentId=s.StudentId
    WHERE LEFT(s.StudentCode,LEN(@Prefix))=@Prefix GROUP BY s.StudentId,s.IsActive
)
SELECT IsActive,UsageRows,COUNT(*) AS Students FROM StudentCounts
GROUP BY IsActive,UsageRows ORDER BY IsActive DESC,UsageRows;

-- Expected: 2026-09-01 through 2026-09-30; all violation counts zero.
SELECT MIN(u.UsageDate) AS MinimumDate,MAX(u.UsageDate) AS MaximumDate,
    SUM(CASE WHEN u.UsageDate<'20260901' OR u.UsageDate>='20261001' THEN 1 ELSE 0 END) AS DatesOutsideSeptember,
    SUM(CASE WHEN u.UsageSeconds<0 THEN 1 ELSE 0 END) AS NegativeDurations,
    SUM(CASE WHEN s.IsActive=0 THEN 1 ELSE 0 END) AS InactiveUsageRows,
    SUM(CASE WHEN u.UsageType NOT IN (N'Video',N'Activity',N'Surfing',N'PDF',N'Assessment',N'Offline')
        THEN 1 ELSE 0 END) AS InvalidTypes
FROM dbo.StudentUsage u JOIN dbo.Students s ON s.StudentId=u.StudentId
WHERE LEFT(s.StudentCode,LEN(@Prefix))=@Prefix;
SELECT u.UsageType,COUNT_BIG(*) AS UsageRows,MIN(u.UsageSeconds) AS MinimumSeconds,
    MAX(u.UsageSeconds) AS MaximumSeconds
FROM dbo.StudentUsage u JOIN dbo.Students s ON s.StudentId=u.StudentId
WHERE LEFT(s.StudentCode,LEN(@Prefix))=@Prefix GROUP BY u.UsageType ORDER BY u.UsageType;

-- Expected hierarchy: 2 blocks/district, 2 clusters/block, 2 schools/cluster.
SELECT d.DistrictName,COUNT(b.BlockId) AS Blocks FROM dbo.Districts d
LEFT JOIN dbo.Blocks b ON b.DistrictId=d.DistrictId
WHERE LEFT(d.DistrictName,LEN(@Prefix))=@Prefix GROUP BY d.DistrictName;
SELECT b.BlockName,COUNT(c.ClusterId) AS Clusters FROM dbo.Blocks b
LEFT JOIN dbo.Clusters c ON c.BlockId=b.BlockId
WHERE LEFT(b.BlockName,LEN(@Prefix))=@Prefix GROUP BY b.BlockName;
SELECT c.ClusterName,COUNT(sc.SchoolId) AS Schools FROM dbo.Clusters c
LEFT JOIN dbo.Schools sc ON sc.ClusterId=c.ClusterId
WHERE LEFT(c.ClusterName,LEN(@Prefix))=@Prefix GROUP BY c.ClusterName;

-- Database-wide orphan check: expected zero for all five relationships.
SELECT N'Blocks -> Districts' AS Relationship,COUNT_BIG(*) AS Orphans
FROM dbo.Blocks b LEFT JOIN dbo.Districts d ON d.DistrictId=b.DistrictId WHERE d.DistrictId IS NULL
UNION ALL SELECT N'Clusters -> Blocks',COUNT_BIG(*) FROM dbo.Clusters c
LEFT JOIN dbo.Blocks b ON b.BlockId=c.BlockId WHERE b.BlockId IS NULL
UNION ALL SELECT N'Schools -> Clusters',COUNT_BIG(*) FROM dbo.Schools sc
LEFT JOIN dbo.Clusters c ON c.ClusterId=sc.ClusterId WHERE c.ClusterId IS NULL
UNION ALL SELECT N'Students -> Schools',COUNT_BIG(*) FROM dbo.Students s
LEFT JOIN dbo.Schools sc ON sc.SchoolId=s.SchoolId WHERE sc.SchoolId IS NULL
UNION ALL SELECT N'StudentUsage -> Students',COUNT_BIG(*) FROM dbo.StudentUsage u
LEFT JOIN dbo.Students s ON s.StudentId=u.StudentId WHERE s.StudentId IS NULL;
GO
