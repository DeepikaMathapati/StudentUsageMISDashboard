using Microsoft.Extensions.Diagnostics.HealthChecks;
using StudentUsageMISDashboard.Data;

var checkDatabase = args.Contains("--check-database", StringComparer.OrdinalIgnoreCase);
var configurationArgs = args.Where(argument =>
    !string.Equals(argument, "--check-database", StringComparison.OrdinalIgnoreCase)).ToArray();
var builder = WebApplication.CreateBuilder(configurationArgs);

// Add services to the container.
builder.Services.AddControllersWithViews();
builder.Services.AddScoped<DashboardRepository>();
builder.Services.AddHealthChecks()
    .AddCheck<DatabaseConnectivityCheck>("database", tags: new[] { "database" });

var app = builder.Build();

// Explicit diagnostic mode: check connectivity and exit without starting MVC.
if (checkDatabase)
{
    using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(20));
    try
    {
        var healthChecks = app.Services.GetRequiredService<HealthCheckService>();
        var report = await healthChecks.CheckHealthAsync(
            registration => registration.Tags.Contains("database"), timeout.Token);
        Console.WriteLine(report.Status == HealthStatus.Healthy
            ? "Database connectivity check succeeded."
            : "Database connectivity check failed. Check your local database and configuration.");
        Environment.ExitCode = report.Status == HealthStatus.Healthy ? 0 : 1;
    }
    catch (OperationCanceledException)
    {
        Console.WriteLine("Database connectivity check timed out.");
        Environment.ExitCode = 1;
    }

    await app.DisposeAsync();
    return;
}

// Configure the HTTP request pipeline.
if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Home/Error");
    // The default HSTS value is 30 days. You may want to change this for production scenarios, see https://aka.ms/aspnetcore-hsts.
    app.UseHsts();
}

app.UseHttpsRedirection();
app.UseStaticFiles();

app.UseRouting();

app.UseAuthorization();

app.MapControllerRoute(
    name: "default",
    pattern: "{controller=Home}/{action=Index}/{id?}");

app.Run();
