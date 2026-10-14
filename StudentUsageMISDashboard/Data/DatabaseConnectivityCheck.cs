using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Diagnostics.HealthChecks;

namespace StudentUsageMISDashboard.Data;

/// <summary>
/// Checks whether the configured database can be opened, without executing SQL.
/// Failure results intentionally exclude connection details and exceptions.
/// </summary>
public sealed class DatabaseConnectivityCheck(IConfiguration configuration) : IHealthCheck
{
    public async Task<HealthCheckResult> CheckHealthAsync(
        HealthCheckContext context,
        CancellationToken cancellationToken = default)
    {
        var connectionString = configuration.GetConnectionString("DefaultConnection");
        if (string.IsNullOrWhiteSpace(connectionString))
        {
            return HealthCheckResult.Unhealthy("Database configuration is unavailable.");
        }

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);
            return HealthCheckResult.Healthy("Database connection succeeded.");
        }
        catch (SqlException)
        {
            return HealthCheckResult.Unhealthy("Database connection failed.");
        }
        catch (ArgumentException)
        {
            return HealthCheckResult.Unhealthy("Database configuration is invalid.");
        }
        catch (InvalidOperationException)
        {
            return HealthCheckResult.Unhealthy("Database connection could not be opened.");
        }
    }
}
