@echo off
chcp 65001 >nul
cd /d "%~dp0"

echo 正在打包华章日新...

REM 删除旧的打包文件夹（如果存在）
if exist "dist" rd /s /q "dist"

REM 创建临时 dist 目录，把 Release 文件夹复制进去
mkdir "dist\华章日新"
xcopy /e /y "build\windows\x64\runner\Release\*" "dist\华章日新\"

REM 复制启动脚本到 dist\华章日新 目录
if exist "build\windows\x64\runner\Release\启动华章日新.bat" (
    copy /y "build\windows\x64\runner\Release\启动华章日新.bat" "dist\华章日新\"
) else (
    echo 警告: 未找到启动脚本，请先在Release文件夹中创建“启动华章日新.bat”
)

REM 使用PowerShell压缩为zip
powershell -command "Compress-Archive -Path 'dist\华章日新' -DestinationPath '华章日新.zip' -Force"

REM 清理临时目录
rd /s /q "dist"

echo.
echo 打包完成！文件：华章日新.zip
pause