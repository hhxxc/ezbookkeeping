@echo off
chcp 65001 >nul

set REPO=hhxxc/ezbookkeeping
set KEEP=20

echo ========================================
echo  Cleanup: GitHub Releases ^& DockerHub
echo  Repo: %REPO%
echo  Keep latest: %KEEP%
echo ========================================
echo.

REM ============================
REM 1. Cleanup GitHub Releases
REM ============================
echo [1/2] Fetching GitHub Releases...
echo.

for /f "skip=%KEEP% delims=" %%i in ('gh release list --repo %REPO% --limit 100 --json tagName,createdAt --jq "sort_by(.createdAt) | reverse | .[].tagName" 2^>nul') do (
    echo   Deleting release: %%i
    gh release delete "%%i" --repo %REPO% --yes 2>nul
)

echo.
echo GitHub Releases cleanup done.
echo.
echo ========================================
echo.
echo [2/2] Fetching DockerHub tags...
echo.

REM ============================
REM 2. Cleanup DockerHub
REM ============================

set DOCKER_USER=hhxxc
set DOCKER_IMAGE=nestkeep
set DOCKER_TOKEN=

echo DockerHub Access Token required.
echo Create one at: https://hub.docker.com/settings/security
echo.
set /p DOCKER_TOKEN=Enter DockerHub Access Token:

if "%DOCKER_TOKEN%"=="" (
    echo [SKIP] No token provided, skipping DockerHub cleanup.
    goto :skip_docker
)

echo.
echo Fetching DockerHub tags...

curl -s -H "Authorization: Bearer %DOCKER_TOKEN%" ^
  "https://hub.docker.com/v2/repositories/%DOCKER_USER%/%DOCKER_IMAGE%/tags/?page_size=100" ^
  > "%TEMP%\docker_tags.json"

set COUNT=0
for /f "tokens=*" %%i in ('jq -r ".results | sort_by(.last_updated) | reverse | .[].name" "%TEMP%\docker_tags.json" 2^>nul') do (
    set /a COUNT+=1
    setlocal enabledelayedexpansion
    if !COUNT! gtr %KEEP% (
        echo   Deleting tag: %%i
        curl -s -X DELETE -H "Authorization: Bearer %DOCKER_TOKEN%" ^
          "https://hub.docker.com/v2/repositories/%DOCKER_USER%/%DOCKER_IMAGE%/tags/%%i/" >nul
    )
    endlocal
)

del "%TEMP%\docker_tags.json" 2>nul
echo.
echo DockerHub cleanup done.

:skip_docker

echo.
echo ========================================
echo  All done!
echo ========================================
pause
