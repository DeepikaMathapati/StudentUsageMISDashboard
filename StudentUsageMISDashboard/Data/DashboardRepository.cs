using System.Data;
using Microsoft.Data.SqlClient;
using StudentUsageMISDashboard.Models;

namespace StudentUsageMISDashboard.Data;

public sealed class DashboardRepository(IConfiguration configuration)
{
    public async Task<DashboardViewModel> LoadAsync(DashboardFilter filter, CancellationToken cancellationToken)
    {
        await using var connection = new SqlConnection(configuration.GetConnectionString("DefaultConnection"));
        await connection.OpenAsync(cancellationToken);
        var model = new DashboardViewModel { Filter = filter };
        await using (var metadata = connection.CreateCommand())
        {
            metadata.CommandText = "SELECT MIN(UsageDate), MAX(UsageDate) FROM dbo.StudentUsage; SELECT DISTINCT UsageType FROM dbo.StudentUsage ORDER BY UsageType;";
            await using var reader = await metadata.ExecuteReaderAsync(cancellationToken);
            await reader.ReadAsync(cancellationToken);
            filter.From ??= reader.IsDBNull(0) ? DateTime.Today.AddDays(-29) : reader.GetDateTime(0);
            filter.To ??= reader.IsDBNull(1) ? DateTime.Today : reader.GetDateTime(1);
            await reader.NextResultAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken)) model.UsageTypes.Add(reader.GetString(0));
        }
        filter.From = filter.From.Value.Date;
        filter.To = filter.To.Value.Date;
        if (filter.From > filter.To) throw new ArgumentException("From date must be on or before To date.");
        if (filter.Unit is not ("Minutes" or "Hours" or "Seconds")) throw new ArgumentException("Choose a valid duration unit.");
        if (filter.UsageType != "All" && !model.UsageTypes.Contains(filter.UsageType)) throw new ArgumentException("Choose a valid usage type.");

        await using var command = connection.CreateCommand();
        command.Parameters.Add("@From", SqlDbType.Date).Value = filter.From.Value;
        command.Parameters.Add("@To", SqlDbType.Date).Value = filter.To.Value;
        command.Parameters.Add("@Type", SqlDbType.NVarChar, 256).Value = filter.UsageType;
        command.CommandText = """
            SELECT u.StudentId, u.UsageDate, u.UsageSeconds
            INTO #Usage
            FROM dbo.StudentUsage u
            WHERE u.UsageDate >= @From AND u.UsageDate <= @To AND (@Type = N'All' OR u.UsageType = @Type);

            SELECT s.StudentId, s.SchoolId, s.IsActive, sc.SchoolCode, sc.SchoolName, d.DistrictId, d.DistrictName
            INTO #Students
            FROM dbo.Students s
            JOIN dbo.Schools sc ON sc.SchoolId = s.SchoolId
            JOIN dbo.Clusters c ON c.ClusterId = sc.ClusterId
            JOIN dbo.Blocks b ON b.BlockId = c.BlockId
            JOIN dbo.Districts d ON d.DistrictId = b.DistrictId;

            SELECT (SELECT COUNT(*) FROM dbo.Schools), (SELECT COUNT(*) FROM dbo.Students),
                (SELECT COUNT(*) FROM dbo.Students WHERE IsActive = 1),
                COUNT(DISTINCT CASE WHEN UsageSeconds > 0 THEN StudentId END), COUNT_BIG(*), COALESCE(SUM(UsageSeconds), 0)
            FROM #Usage;

            WITH Totals AS (
                SELECT s.StudentId, COALESCE(SUM(u.UsageSeconds), 0) Seconds
                FROM dbo.Students s LEFT JOIN #Usage u ON u.StudentId = s.StudentId GROUP BY s.StudentId
            ), Classified AS (
                SELECT CASE WHEN Seconds <= 0 THEN 0 WHEN Seconds <= 300 THEN 1 WHEN Seconds <= 900 THEN 2
                    WHEN Seconds <= 1800 THEN 3 WHEN Seconds <= 2700 THEN 4 ELSE 5 END Bucket FROM Totals
            )
            SELECT b.Label, COUNT(c.Bucket) FROM (VALUES (0, N'No usage'), (1, N'>0–5 min'), (2, N'>5–15 min'),
                (3, N'>15–30 min'), (4, N'>30–45 min'), (5, N'>45 min')) b(Id, Label)
            LEFT JOIN Classified c ON c.Bucket = b.Id GROUP BY b.Id, b.Label ORDER BY b.Id;

            SELECT d.DistrictName, COUNT(DISTINCT CASE WHEN u.UsageSeconds > 0 THEN s.StudentId END),
                COALESCE(SUM(u.UsageSeconds), 0), COUNT(DISTINCT s.StudentId)
            FROM dbo.Districts d LEFT JOIN #Students s ON s.DistrictId = d.DistrictId
            LEFT JOIN #Usage u ON u.StudentId = s.StudentId GROUP BY d.DistrictId, d.DistrictName ORDER BY d.DistrictName;

            SELECT CONVERT(char(10), UsageDate, 23), COUNT(DISTINCT CASE WHEN UsageSeconds > 0 THEN StudentId END),
                COALESCE(SUM(UsageSeconds), 0) FROM #Usage GROUP BY UsageDate ORDER BY UsageDate;

            SELECT CONCAT(d.DistrictName, N' / ', sc.SchoolCode, N' / ', sc.SchoolName),
                COUNT(DISTINCT CASE WHEN u.UsageSeconds > 0 THEN s.StudentId END), COALESCE(SUM(u.UsageSeconds), 0),
                COUNT(DISTINCT s.StudentId)
            FROM dbo.Schools sc JOIN dbo.Clusters c ON c.ClusterId = sc.ClusterId
            JOIN dbo.Blocks b ON b.BlockId = c.BlockId JOIN dbo.Districts d ON d.DistrictId = b.DistrictId
            LEFT JOIN dbo.Students s ON s.SchoolId = sc.SchoolId LEFT JOIN #Usage u ON u.StudentId = s.StudentId
            GROUP BY sc.SchoolId, sc.SchoolCode, sc.SchoolName, d.DistrictName ORDER BY d.DistrictName, sc.SchoolName;

            SELECT CONVERT(char(7), UsageDate, 23), COUNT(DISTINCT CASE WHEN UsageSeconds > 0 THEN StudentId END),
                COALESCE(SUM(UsageSeconds), 0) FROM #Usage GROUP BY CONVERT(char(7), UsageDate, 23) ORDER BY 1;
            SELECT CONVERT(char(4), YEAR(UsageDate)), COUNT(DISTINCT CASE WHEN UsageSeconds > 0 THEN StudentId END),
                COALESCE(SUM(UsageSeconds), 0) FROM #Usage GROUP BY YEAR(UsageDate) ORDER BY 1;
            """;
        await using var results = await command.ExecuteReaderAsync(cancellationToken);
        await results.ReadAsync(cancellationToken);
        model.Schools = results.GetInt32(0);
        model.Students = results.GetInt32(1);
        model.ActiveAccounts = results.GetInt32(2);
        model.StudentsWithUsage = results.GetInt32(3);
        model.UsageRecords = results.GetInt64(4);
        model.TotalSeconds = results.GetDecimal(5);
        await results.NextResultAsync(cancellationToken);
        while (await results.ReadAsync(cancellationToken)) model.Buckets.Add(new(results.GetString(0), results.GetInt32(1)));
        foreach (var list in new[] { model.Districts, model.Daily, model.SchoolDetails, model.Monthly, model.Yearly })
        {
            await results.NextResultAsync(cancellationToken);
            while (await results.ReadAsync(cancellationToken))
                list.Add(new(results.GetString(0), results.GetInt32(1), results.GetDecimal(2), results.FieldCount > 3 ? results.GetInt32(3) : 0));
        }
        return model;
    }
}
