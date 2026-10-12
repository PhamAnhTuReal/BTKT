FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build

WORKDIR /src
COPY ["src/PAT.MyProject.Web.Host/PAT.MyProject.Web.Host.csproj", "src/PAT.MyProject.Web.Host/"]
COPY ["src/PAT.MyProject.Web.Core/PAT.MyProject.Web.Core.csproj", "src/PAT.MyProject.Web.Core/"]
COPY ["src/PAT.MyProject.Application/PAT.MyProject.Application.csproj", "src/PAT.MyProject.Application/"]
COPY ["src/PAT.MyProject.Core/PAT.MyProject.Core.csproj", "src/PAT.MyProject.Core/"]
COPY ["src/PAT.MyProject.EntityFrameworkCore/PAT.MyProject.EntityFrameworkCore.csproj", "src/PAT.MyProject.EntityFrameworkCore/"]
WORKDIR "/src/src/PAT.MyProject.Web.Host"
RUN dotnet restore 

WORKDIR /src
COPY ["src/PAT.MyProject.Web.Host", "src/PAT.MyProject.Web.Host"]
COPY ["src/PAT.MyProject.Web.Core", "src/PAT.MyProject.Web.Core"]
COPY ["src/PAT.MyProject.Application", "src/PAT.MyProject.Application"]
COPY ["src/PAT.MyProject.Core", "src/PAT.MyProject.Core"]
COPY ["src/PAT.MyProject.EntityFrameworkCore", "src/PAT.MyProject.EntityFrameworkCore"]
WORKDIR "/src/src/PAT.MyProject.Web.Host"
RUN dotnet publish -c Release -o /publish --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:8.0
EXPOSE 80
WORKDIR /app
COPY --from=build /publish .
ENTRYPOINT ["dotnet", "PAT.MyProject.Web.Host.dll"]
