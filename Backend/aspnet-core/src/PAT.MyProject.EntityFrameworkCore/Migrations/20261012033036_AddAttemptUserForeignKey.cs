using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace PAT.MyProject.Migrations
{
    /// <inheritdoc />
    public partial class AddAttemptUserForeignKey : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddForeignKey(
                name: "FK_Attempts_AbpUsers",
                table: "ExamAttempts",
                column: "UserId",
                principalTable: "AbpUsers",
                principalColumn: "Id");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_Attempts_AbpUsers",
                table: "ExamAttempts");
        }
    }
}
