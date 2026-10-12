using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text;
using System.Xml.Linq;
using PAT.MyProject.Web.Services;
using Shouldly;
using Xunit;

namespace PAT.MyProject.Web.Tests.Services;

public class ToeicDocxParserTests
{
    [Fact]
    public void Parse_reads_questions_options_and_group_passages_from_docx()
    {
        using var docx = CreateDocx(CreateReadingMarkup());

        var exam = new ToeicDocxParser().Parse(docx);

        exam.Name.ShouldBe("RC Test 01");
        exam.DurationMinutes.ShouldBe(75);
        exam.Parts.Count.ShouldBe(3);
        exam.Parts.Sum(part => part.Questions.Count).ShouldBe(100);
        exam.Parts[0].Questions[0].Number.ShouldBe(101);
        exam.Parts[0].Questions[0].Options.Count.ShouldBe(4);
        exam.Parts[1].Groups.Single().FromNumber.ShouldBe(131);
        exam.Parts[2].Groups.Single().Passages.Single().Content.ShouldBe("Sample passage.");
        exam.Parts[2].Questions.Last().Number.ShouldBe(200);
    }

    [Fact]
    public void Parse_rejects_a_docx_without_the_expected_exam_markup()
    {
        using var docx = CreateDocx("ordinary Word content");

        Should.Throw<InvalidDataException>(() => new ToeicDocxParser().Parse(docx));
    }

    private static MemoryStream CreateDocx(string markup)
    {
        XNamespace word = "http://schemas.openxmlformats.org/wordprocessingml/2006/main";
        var document = new XDocument(
            new XElement(
                word + "document",
                new XElement(
                    word + "body",
                    new XElement(
                        word + "p",
                        new XElement(
                            word + "r",
                            new XElement(word + "t", markup))))));
        var stream = new MemoryStream();
        using (var archive = new ZipArchive(stream, ZipArchiveMode.Create, leaveOpen: true))
        using (var documentStream = archive.CreateEntry("word/document.xml").Open())
        {
            document.Save(documentStream);
        }

        stream.Position = 0;
        return stream;
    }

    private static string CreateReadingMarkup()
    {
        var builder = new StringBuilder("<de ten=\"RC Test 01\" thoigian=\"75\">");
        builder.Append("<part so=\"5\"><hd>Part 5 directions</hd>");
        AppendQuestions(builder, 101, 130);
        builder.Append("</part><part so=\"6\"><hd>Part 6 directions</hd>");
        builder.Append("<nhom tu=\"131\" den=\"146\"><tl>Part 6 group</tl>");
        AppendQuestions(builder, 131, 146);
        builder.Append("</nhom></part><part so=\"7\"><hd>Part 7 directions</hd>");
        builder.Append("<nhom tu=\"147\" den=\"200\"><tl>Part 7 group</tl>");
        builder.Append("<dv loai=\"article\">Sample passage.</dv>");
        AppendQuestions(builder, 147, 200);
        builder.Append("</nhom></part></de>");
        return builder.ToString();
    }

    private static void AppendQuestions(StringBuilder builder, int from, int to)
    {
        for (var number = from; number <= to; number++)
        {
            builder.Append("<cau so=\"")
                .Append(number)
                .Append("\"><ch>Question ")
                .Append(number)
                .Append("?</ch>");
            foreach (var label in new[] { "A", "B", "C", "D" })
            {
                builder.Append("<ctrl ma=\"")
                    .Append(label)
                    .Append("\">Option ")
                    .Append(label)
                    .Append("</ctrl>");
            }

            builder.Append("<dn>A</dn></cau>");
        }
    }
}
