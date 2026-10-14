namespace StudentUsageMISDashboard.Models;

public sealed class DashboardFilter
{
    public DateTime? From { get; set; }
    public DateTime? To { get; set; }
    public string UsageType { get; set; } = "All";
    public string Unit { get; set; } = "Minutes";
}

public sealed record UsageSummary(string Name, int Students, decimal Seconds, int Registered = 0);
public sealed record UsageBucket(string Name, int Students);

public sealed class DashboardViewModel
{
    public DashboardFilter Filter { get; set; } = new();
    public List<string> UsageTypes { get; set; } = [];
    public int Schools { get; set; }
    public int Students { get; set; }
    public int ActiveAccounts { get; set; }
    public int StudentsWithUsage { get; set; }
    public long UsageRecords { get; set; }
    public decimal TotalSeconds { get; set; }
    public List<UsageBucket> Buckets { get; set; } = [];
    public List<UsageSummary> Districts { get; set; } = [];
    public List<UsageSummary> Daily { get; set; } = [];
    public List<UsageSummary> SchoolDetails { get; set; } = [];
    public List<UsageSummary> Monthly { get; set; } = [];
    public List<UsageSummary> Yearly { get; set; } = [];
    public string? Error { get; set; }
    public decimal Duration(decimal seconds) => seconds / (Filter.Unit == "Hours" ? 3600m : Filter.Unit == "Seconds" ? 1m : 60m);
}
