using System.ComponentModel.DataAnnotations;

namespace PAT.MyProject.Users.Dto;

public class ChangeUserLanguageDto
{
    [Required]
    public string LanguageName { get; set; }
}