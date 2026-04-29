# start-dev.ps1
Write-Host "Starting ezBookkeeping development environment..." -ForegroundColor Green

# 启动前端服务（后台）
Start-Process powershell -ArgumentList "-NoExit", "-Command", "npm run serve"

# 等待2秒让前端先启动
Start-Sleep -Seconds 2

# 启动后端服务（后台）
Start-Process powershell -ArgumentList "-NoExit", "-Command", "`$env:Path = 'C:\msys64\mingw64\bin;' + `$env:Path; `$env:CGO_ENABLED='1'; air"

Write-Host "Both services started!" -ForegroundColor Green
Write-Host "Frontend: http://localhost:28081/" -ForegroundColor Cyan
Write-Host "Backend (access this): http://localhost:15080/" -ForegroundColor Cyan
