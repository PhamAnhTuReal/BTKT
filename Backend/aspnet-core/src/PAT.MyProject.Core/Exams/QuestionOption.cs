#nullable enable
namespace PAT.MyProject.Exams;

public class QuestionOption
{
    public int Id { get; set; }
    public int QuestionId { get; set; }
    public string Label { get; set; } = string.Empty;
    public string Content { get; set; } = string.Empty;

    public Question Question { get; set; } = null!;
}
