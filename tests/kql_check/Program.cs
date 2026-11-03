// Parses every detections/**/rule.kql and functions/*.kql with Microsoft's Kusto.Language
// parser and fails on any syntax error. Usage: dotnet run --project tests/kql_check -- <repo root>
using Kusto.Language;

var root = args.Length > 0 ? args[0] : ".";
var files = Directory.GetFiles(Path.Combine(root, "detections"), "rule.kql", SearchOption.AllDirectories)
    .Concat(Directory.GetFiles(Path.Combine(root, "functions"), "*.kql"))
    .OrderBy(f => f, StringComparer.Ordinal)
    .ToList();

if (files.Count == 0)
{
    Console.Error.WriteLine("no .kql files found");
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
        Console.WriteLine($"ok    {rel}");
        continue;
    }
    failed++;
    foreach (var d in errors)
    {
        var line = text.Take(d.Start).Count(c => c == '\n') + 1;
        Console.WriteLine($"ERROR {rel}:{line}: {d.Message}");
        // GitHub annotation, shown on the file in the pull request / run summary
        Console.WriteLine($"::error file={rel},line={line}::KQL syntax: {d.Message}");
    }
}

Console.WriteLine($"{files.Count - failed}/{files.Count} files parsed without syntax errors");
return failed == 0 ? 0 : 1;
