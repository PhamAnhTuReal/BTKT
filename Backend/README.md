# Important

Issues of this repository are tracked on https://github.com/aspnetboilerplate/aspnetboilerplate. Please create your issues on https://github.com/aspnetboilerplate/aspnetboilerplate/issues.

# Introduction

This is a template to create **ASP.NET Core MVC / Angular** based startup projects for [ASP.NET Boilerplate](https://aspnetboilerplate.com/Pages/Documents). It has 2 different versions:

1. [ASP.NET Core MVC & jQuery](https://aspnetboilerplate.com/Pages/Documents/Zero/Startup-Template-Core) (server rendered multi-page application).
2. [ASP.NET Core & Angular](https://aspnetboilerplate.com/Pages/Documents/Zero/Startup-Template-Angular) (single page application).
 
User Interface is based on [AdminLTE theme](https://github.com/ColorlibHQ/AdminLTE).
 
# Download

Create & download your project from https://aspnetboilerplate.com/Templates

# Run the MVC admin interface locally

The MVC project builds its AdminLTE styles and scripts from `bundles.json`. Restore the frontend dependencies and create the bundles before starting the web project:

```powershell
cd Backend\aspnet-core\src\PAT.MyProject.Web.Mvc
npx --yes yarn@1.22.22 install --frozen-lockfile
npx gulp build
dotnet run
```

Open `https://localhost:44312` after the application starts. If the interface appears unstyled, make sure the bundle build completed and reload the page with `Ctrl+F5`.

## Upload and run a TOEIC Reading exam

Start the MVC admin and the API in separate terminals:

```powershell
cd Backend\aspnet-core\src\PAT.MyProject.Web.Mvc
dotnet run
```

```powershell
dotnet run --project .\Backend\aspnet-core\src\PAT.MyProject.Web.Host\PAT.MyProject.Web.Host.csproj --launch-profile "Toeic HTTP"
```

Run the command from the repository root. If already inside `Backend\aspnet-core\src\PAT.MyProject.Web.Host`, use `dotnet run --launch-profile "Toeic HTTP"` instead.

Open `https://localhost:44312` in the admin, then upload a `.docx` file from the home page. The file must contain the tagged Reading format used by `RC_Test01_tags.docx`, with Part 5–7 and questions 101–200. The attached `Đề thi giữa kỳ.pdf` is a four-page assignment/instructions document describing how to create the tagged Word file; it is not accepted as an exam upload. A successful DOCX upload is saved in SQL Server and becomes the published exam; the previous published exam is retained but unpublished. Use **Chỉnh sửa** beside an uploaded exam to update its title, duration, directions, passages, question text, answer choices, and correct answers. Changes to the published exam are returned by the API on the next request.

Run the Flutter app against the local API:

```powershell
cd bai_kt
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5000
```

`10.0.2.2` is the Android emulator's address for the development computer. For Flutter Web, use `--dart-define=API_BASE_URL=http://localhost:5000`; localhost web origins on any port are allowed by the API only in Development. For a physical phone, use the computer's LAN IP instead. The HTTP launch profile and Android debug cleartext traffic setting are for local development only; do not expose them in production. The Flutter client unwraps the ABP `{ "result": ... }` response returned by the API.

If the API is stopped or no exam is published, the Flutter app still opens its home screen and offers a retry action. Start the Host API and publish an exam from the admin to enable the test-taking screen.

# Screenshots

#### Sample Dashboard Page
![](_screenshots/module-zero-core-template-ui-home.png)

#### User Creation Modal
![](_screenshots/module-zero-core-template-ui-user-create-modal.png)

#### Login Page

![](_screenshots/module-zero-core-template-ui-login.png)

# Documentation

* [ASP.NET Core MVC & jQuery version.](https://aspnetboilerplate.com/Pages/Documents/Zero/Startup-Template-Core)
* [ASP.NET Core & Angular  version.](https://aspnetboilerplate.com/Pages/Documents/Zero/Startup-Template-Angular)

# License

[MIT](LICENSE).
