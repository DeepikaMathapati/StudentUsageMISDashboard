using System.Diagnostics;
using System.Globalization;
using System.Text;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using StudentUsageMISDashboard.Data;
using StudentUsageMISDashboard.Models;

namespace StudentUsageMISDashboard.Controllers;

public class HomeController(DashboardRepository repository, ILogger<HomeController> logger) : Controller
{
    public async Task<IActionResult> Index([FromQuery] DashboardFilter filter, CancellationToken cancellationToken)
    {
        if (!ModelState.IsValid)
            return View(new DashboardViewModel { Filter = filter, Error = "Please enter valid filter values." });
        try { return View(await repository.LoadAsync(filter, cancellationToken)); }
        catch (ArgumentException exception)
        {
            return View(new DashboardViewModel { Filter = filter, Error = exception.Message });
        }
        catch (SqlException exception)
        {
            logger.LogError(exception, "Unable to load dashboard data.");
            Response.StatusCode = 503;
            return View(new DashboardViewModel { Filter = filter, Error = "SQL Server data is currently unavailable. Please try again." });
        }
    }

    [HttpGet]
    public async Task<IActionResult> Report(string kind, [FromQuery] DashboardFilter filter, CancellationToken cancellationToken)
    {
        if (!ModelState.IsValid) return BadRequest("Please enter valid filter values.");
        if (kind is not ("district" or "daily" or "school" or "monthly" or "yearly")) return BadRequest("Unknown report.");
        DashboardViewModel model;
        try { model = await repository.LoadAsync(filter, cancellationToken); }
        catch (ArgumentException exception) { return BadRequest(exception.Message); }
        catch (SqlException exception)
        {
            logger.LogError(exception, "Unable to load report data.");
            return StatusCode(503, "SQL Server data is currently unavailable. Please try again.");
        }
        var rows = kind switch
        {
            "district" => model.Districts, "daily" => model.Daily, "school" => model.SchoolDetails,
            "monthly" => model.Monthly, _ => model.Yearly
        };
        var csv = new StringBuilder();
        csv.AppendLine("From date,To date,Usage type,Duration unit");
        csv.AppendLine($"{filter.From:yyyy-MM-dd},{filter.To:yyyy-MM-dd},{Cell(filter.UsageType)},{filter.Unit}");
        csv.AppendLine();
        csv.AppendLine($"{(kind == "school" ? "District / School code / School" : "Period or district")},Students with usage,Usage ({filter.Unit.ToLowerInvariant()}){(kind is "district" or "school" ? ",Registered students" : "")}");
        foreach (var row in rows)
        {
            csv.Append($"{Cell(row.Name)},{row.Students},{model.Duration(row.Seconds).ToString("0.######", CultureInfo.InvariantCulture)}");
            if (kind is "district" or "school") csv.Append($",{row.Registered}");
            csv.AppendLine();
        }
        return File(Encoding.UTF8.GetPreamble().Concat(Encoding.UTF8.GetBytes(csv.ToString())).ToArray(), "text/csv", $"student-{kind}-{filter.From:yyyyMMdd}-{filter.To:yyyyMMdd}.csv");
    }

    private static string Cell(string value)
    {
        if (value.TrimStart().StartsWith('=') || value.TrimStart().StartsWith('+') || value.TrimStart().StartsWith('-') || value.TrimStart().StartsWith('@')) value = "'" + value;
        return "\"" + value.Replace("\"", "\"\"") + "\"";
    }

    public IActionResult Privacy() => View();

    [ResponseCache(Duration = 0, Location = ResponseCacheLocation.None, NoStore = true)]
    public IActionResult Error() => View(new ErrorViewModel { RequestId = Activity.Current?.Id ?? HttpContext.TraceIdentifier });
}
