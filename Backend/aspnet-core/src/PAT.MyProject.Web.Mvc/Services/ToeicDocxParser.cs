#nullable enable
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net;
using System.Text.RegularExpressions;
using System.Xml;
using System.Xml.Linq;

namespace PAT.MyProject.Web.Services;

public sealed class ToeicDocxParser
{
    private const long MaxDocumentXmlBytes = 10 * 1024 * 1024;
    private static readonly Regex PartRegex = new(
        @"<part\b(?<attributes>[^>]*)>(?<body>[\s\S]*?)</part>",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
    private static readonly Regex GroupRegex = new(
        @"<nhom\b(?<attributes>[^>]*)>(?<body>[\s\S]*?)</nhom>",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
    private static readonly Regex QuestionRegex = new(
        @"<cau\b(?<attributes>[^>]*)>(?<body>[\s\S]*?)</cau>",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
    private static readonly Regex PassageRegex = new(
        @"<dv\b(?<attributes>[^>]*)>(?<body>[\s\S]*?)</dv>",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
    private static readonly Regex AttributeRegex = new(
        @"(?<name>[A-Za-z_]\w*)\s*=\s*(?:""(?<double>[^""]*)""|'(?<single>[^']*)')",
        RegexOptions.CultureInvariant);

    public ParsedToeicExam Parse(Stream docxStream)
    {
        using var archive = new ZipArchive(docxStream, ZipArchiveMode.Read, leaveOpen: true);
        var documentEntry = archive.GetEntry("word/document.xml")
            ?? throw new InvalidDataException("Tệp không phải là tài liệu Word .docx hợp lệ.");

        if (documentEntry.Length > MaxDocumentXmlBytes)
        {
            throw new InvalidDataException("Nội dung tài liệu vượt quá giới hạn cho phép.");
        }

        string documentText;
        using (var entryStream = documentEntry.Open())
        using (var reader = XmlReader.Create(entryStream, new XmlReaderSettings
        {
            DtdProcessing = DtdProcessing.Prohibit,
            XmlResolver = null,
            MaxCharactersInDocument = MaxDocumentXmlBytes
        }))
        {
            var document = XDocument.Load(reader);
            XNamespace wordNamespace = "http://schemas.openxmlformats.org/wordprocessingml/2006/main";
            documentText = string.Join(
                "\n",
                document.Descendants(wordNamespace + "p")
                    .Select(paragraph => string.Concat(
                        paragraph.Descendants(wordNamespace + "t").Select(text => text.Value))));
        }

        var examMatch = Regex.Match(
            documentText,
            @"<de\b(?<attributes>[^>]*)>(?<body>[\s\S]*?)</de>",
            RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
        if (!examMatch.Success)
        {
            throw new InvalidDataException("Không tìm thấy thẻ đề <de> trong tài liệu Word.");
        }

        var examAttributes = ParseAttributes(examMatch.Groups["attributes"].Value);
        var name = GetRequiredAttribute(examAttributes, "ten", "Tên đề thi");
        if (name.Length > 200)
        {
            throw new InvalidDataException("Tên đề thi không được dài quá 200 ký tự.");
        }
        if (!int.TryParse(
                GetRequiredAttribute(examAttributes, "thoigian", "Thời gian làm bài"),
                NumberStyles.None,
                CultureInfo.InvariantCulture,
                out var durationMinutes) ||
            durationMinutes is < 1 or > 300)
        {
            throw new InvalidDataException("Thời gian làm bài phải là số phút từ 1 đến 300.");
        }

        var parsedExam = new ParsedToeicExam
        {
            Name = name,
            DurationMinutes = durationMinutes
        };

        foreach (Match partMatch in PartRegex.Matches(examMatch.Groups["body"].Value))
        {
            var partAttributes = ParseAttributes(partMatch.Groups["attributes"].Value);
            if (!byte.TryParse(
                    GetRequiredAttribute(partAttributes, "so", "Số Part"),
                    NumberStyles.None,
                    CultureInfo.InvariantCulture,
                    out var partNumber) ||
                partNumber is < 5 or > 7)
            {
                throw new InvalidDataException("Chỉ hỗ trợ các Part Reading 5, 6 và 7.");
            }

            var partBody = partMatch.Groups["body"].Value;
            var part = new ParsedToeicPart
            {
                PartNumber = partNumber,
                Directions = ExtractTagContent(partBody, "hd")
            };
            var groups = new List<(int From, int To, ParsedToeicGroup Group)>();
            var groupOrder = 0;

            foreach (Match groupMatch in GroupRegex.Matches(partBody))
            {
                var groupAttributes = ParseAttributes(groupMatch.Groups["attributes"].Value);
                if (!int.TryParse(GetRequiredAttribute(groupAttributes, "tu", "Câu bắt đầu của nhóm"), out var from) ||
                    !int.TryParse(GetRequiredAttribute(groupAttributes, "den", "Câu kết thúc của nhóm"), out var to) ||
                    from > to)
                {
                    throw new InvalidDataException("Khoảng số câu của một nhóm câu không hợp lệ.");
                }

                var groupBody = groupMatch.Groups["body"].Value;
                var group = new ParsedToeicGroup
                {
                    FromNumber = from,
                    ToNumber = to,
                    Title = ExtractTagContent(groupBody, "tl"),
                    OrderIndex = groupOrder++,
                    Passages = PassageRegex.Matches(groupBody)
                        .Cast<Match>()
                        .Select((passageMatch, index) => new ParsedToeicPassage
                        {
                            Type = GetAttribute(
                                ParseAttributes(passageMatch.Groups["attributes"].Value),
                                "loai"),
                            Content = DecodeText(passageMatch.Groups["body"].Value),
                            OrderIndex = index
                        })
                        .ToList()
                };
                if (group.Title.Length > 500 ||
                    group.Passages.Any(passage =>
                        passage.Type?.Length > 100))
                {
                    throw new InvalidDataException("Tên nhóm hoặc loại bài đọc vượt quá giới hạn cho phép.");
                }

                groups.Add((from, to, group));
                part.Groups.Add(group);
            }

            foreach (Match questionMatch in QuestionRegex.Matches(partBody))
            {
                var questionAttributes = ParseAttributes(questionMatch.Groups["attributes"].Value);
                if (!int.TryParse(
                        GetRequiredAttribute(questionAttributes, "so", "Số câu"),
                        NumberStyles.None,
                        CultureInfo.InvariantCulture,
                        out var number))
                {
                    throw new InvalidDataException("Số câu hỏi không hợp lệ.");
                }

                var questionBody = questionMatch.Groups["body"].Value;
                var content = ExtractTagContent(questionBody, "ch");
                var options = Regex.Matches(
                        questionBody,
                        @"<ctrl\b(?<attributes>[^>]*)>(?<body>[\s\S]*?)</ctrl>",
                        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)
                    .Cast<Match>()
                    .Select(optionMatch => new ParsedToeicOption
                    {
                        Label = GetRequiredAttribute(
                            ParseAttributes(optionMatch.Groups["attributes"].Value),
                            "ma",
                            "Mã đáp án"),
                        Content = DecodeText(optionMatch.Groups["body"].Value)
                    })
                    .OrderBy(option => option.Label, StringComparer.Ordinal)
                    .ToList();
                var correctAnswer = ExtractTagContent(questionBody, "dn");
                var matchingGroups = groups
                    .Where(group => number >= group.From && number <= group.To)
                    .ToList();

                if (content.Length == 0 ||
                    options.Count != 4 ||
                    options.Select(option => option.Label).Distinct(StringComparer.Ordinal).Count() != 4 ||
                    options.Any(option => option.Label is not ("A" or "B" or "C" or "D") || option.Content.Length == 0) ||
                    correctAnswer is not ("A" or "B" or "C" or "D") ||
                    options.All(option => option.Label != correctAnswer) ||
                    (partNumber == 5 && matchingGroups.Count != 0) ||
                    (partNumber is 6 or 7 && matchingGroups.Count != 1))
                {
                    throw new InvalidDataException($"Câu {number} thiếu nội dung, đáp án hợp lệ hoặc nhóm câu tương ứng.");
                }

                part.Questions.Add(new ParsedToeicQuestion
                {
                    Number = number,
                    Content = content,
                    CorrectAnswer = correctAnswer,
                    Options = options,
                    Group = matchingGroups.Count == 1 ? matchingGroups[0].Group : null
                });
            }

            parsedExam.Parts.Add(part);
        }

        var questions = parsedExam.Parts.SelectMany(part => part.Questions).ToList();
        if (parsedExam.Parts.Select(part => part.PartNumber).Distinct().Count() != 3 ||
            !new byte[] { 5, 6, 7 }.All(number => parsedExam.Parts.Any(part => part.PartNumber == number)) ||
            questions.Count != 100 ||
            questions.Select(question => question.Number).Distinct().Count() != 100 ||
            !Enumerable.Range(101, 100).All(number => questions.Any(question => question.Number == number)))
        {
            throw new InvalidDataException("Đề Reading phải có đủ 100 câu liên tục từ câu 101 đến câu 200, thuộc Part 5–7.");
        }

        if (parsedExam.Parts.Any(part => part.Questions.Any(question =>
                (part.PartNumber == 5 && question.Number is < 101 or > 130) ||
                (part.PartNumber == 6 && question.Number is < 131 or > 146) ||
                (part.PartNumber == 7 && question.Number is < 147 or > 200))))
        {
            throw new InvalidDataException("Số câu không khớp với Part 5, 6 hoặc 7.");
        }

        parsedExam.Parts = parsedExam.Parts.OrderBy(part => part.PartNumber).ToList();
        return parsedExam;
    }

    private static Dictionary<string, string> ParseAttributes(string source)
    {
        return AttributeRegex.Matches(source)
            .Cast<Match>()
            .ToDictionary(
                match => match.Groups["name"].Value,
                match => WebUtility.HtmlDecode(
                    match.Groups["double"].Success
                        ? match.Groups["double"].Value
                        : match.Groups["single"].Value),
                StringComparer.OrdinalIgnoreCase);
    }

    private static string GetRequiredAttribute(
        IReadOnlyDictionary<string, string> attributes,
        string name,
        string label)
    {
        return GetAttribute(attributes, name)
            ?? throw new InvalidDataException($"Thiếu thuộc tính {label} trong tài liệu.");
    }

    private static string? GetAttribute(IReadOnlyDictionary<string, string> attributes, string name)
    {
        return attributes.TryGetValue(name, out var value) ? value : null;
    }

    private static string ExtractTagContent(string source, string tagName)
    {
        var match = Regex.Match(
            source,
            $@"<{Regex.Escape(tagName)}\b[^>]*>(?<body>[\s\S]*?)</{Regex.Escape(tagName)}>",
            RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
        return match.Success ? DecodeText(match.Groups["body"].Value) : string.Empty;
    }

    private static string DecodeText(string value)
    {
        return WebUtility.HtmlDecode(value).Trim();
    }
}

public sealed class ParsedToeicExam
{
    public string Name { get; set; } = string.Empty;
    public int DurationMinutes { get; set; }
    public List<ParsedToeicPart> Parts { get; set; } = new();
}

public sealed class ParsedToeicPart
{
    public byte PartNumber { get; set; }
    public string Directions { get; set; } = string.Empty;
    public List<ParsedToeicGroup> Groups { get; set; } = new();
    public List<ParsedToeicQuestion> Questions { get; set; } = new();
}

public sealed class ParsedToeicGroup
{
    public int FromNumber { get; set; }
    public int ToNumber { get; set; }
    public string Title { get; set; } = string.Empty;
    public int OrderIndex { get; set; }
    public List<ParsedToeicPassage> Passages { get; set; } = new();
}

public sealed class ParsedToeicPassage
{
    public string? Type { get; set; }
    public string Content { get; set; } = string.Empty;
    public int OrderIndex { get; set; }
}

public sealed class ParsedToeicQuestion
{
    public int Number { get; set; }
    public string Content { get; set; } = string.Empty;
    public string CorrectAnswer { get; set; } = string.Empty;
    public List<ParsedToeicOption> Options { get; set; } = new();
    public ParsedToeicGroup? Group { get; set; }
}

public sealed class ParsedToeicOption
{
    public string Label { get; set; } = string.Empty;
    public string Content { get; set; } = string.Empty;
}
