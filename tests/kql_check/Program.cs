// Parses every detections/**/rule.kql and functions/*.kql with Microsoft's Kusto.Language
// parser and fails on any syntax error.
//
// Usage: dotnet run --project tests/kql_check -- <repo root>
//        dotnet run --project tests/kql_check -- --expect-errors <fixture root>
//
// --expect-errors is the self-test: every file under the fixture root must have a syntax error,
// so a parser or checker that silently accepts everything turns CI red. No GitHub annotations are
// written in that mode (the errors are expected).
using Kusto.Language;

var expectErrors = args.Contains("--expect-errors");
var root = args.FirstOrDefault(a => !a.StartsWith("--")) ?? ".";

IEnumerable<string> Find(string dir, string pattern) =>
    Directory.Exists(Path.Combine(root, dir))
        ? Directory.GetFiles(Path.Combine(root, dir), pattern, SearchOption.AllDirectories)
        : Enumerable.Empty<string>();

var files = Find("detections", "rule.kql")
    .Concat(Find("functions", "*.kql"))
    .OrderBy(f => f, StringComparer.Ordinal)
    .ToList();

if (files.Count == 0)
{
    Console.Error.WriteLine($"no .kql files found under {root}");
    return 2;
}

var failed = 0;
foreach (var file in files)
{
    var text = File.ReadAllText(file);
    var code = KustoCode.Parse(text);
    var errors = code.GetSyntaxDiagnostics()
        .Where(d => d.Severity == DiagnosticSeverity.Error)
        .ToList();
    var rel = Path.GetRelativePath(root, file);
    if (errors.Count == 0)
    {
        Console.WriteLine(expectErrors ? $"MISSED {rel}: expected a syntax error, parsed cleanly" : $"ok    {rel}");
        if (expectErrors) Console.WriteLine($"::error file={rel}::KQL checker self-test: broken fixture parsed without errors");
        continue;
    }
    failed++;
    foreach (var d in errors)
    {
        var line = text.Take(d.Start).Count(c => c == '\n') + 1;
        Console.WriteLine($"{(expectErrors ? "caught" : "ERROR")} {rel}:{line}: {d.Message}");
        // GitHub annotation, shown on the file in the pull request / run summary
        if (!expectErrors) Console.WriteLine($"::error file={rel},line={line}::KQL syntax: {d.Message}");
    }
}

if (expectErrors)
{
    Console.WriteLine($"{failed}/{files.Count} broken fixtures rejected");
    return failed == files.Count ? 0 : 1;
}
Console.WriteLine($"{files.Count - failed}/{files.Count} files parsed without syntax errors");
return failed == 0 ? 0 : 1;
